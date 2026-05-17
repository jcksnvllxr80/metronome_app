import Foundation
import CoreMIDI

/// Listens for MIDI Clock + Start/Continue/Stop on every available
/// external MIDI source and drives the engine's tempo + transport from
/// it — spec §12.2 slave mode.
///
/// Architecture: a non-actor `MIDIInputHelper` owns the CoreMIDI handles
/// and the read block (C callbacks can't safely cross actor isolation).
/// The helper forwards each MIDI byte (with a SystemClock-now timestamp)
/// to a closure; the closure schedules a `Task` that re-enters the
/// `MIDIReceiver` actor, where all state mutations happen.
///
/// BPM tracking: 24-tick rolling window. Average inter-tick interval →
/// `BPM(60 / (avgPeriod * 24))`. Engine is only notified when the new
/// BPM differs from the last notified by ≥ 0.5 BPM, to keep small
/// jitter from spamming `setBPM` calls.
public actor MIDIReceiver {
    private let helper: MIDIInputHelper
    private weak var engineRef: MetronomeEngine?

    private var isEnabled: Bool = false
    /// Recent tick arrival times (engine-clock seconds). 24 = one beat
    /// at 24 PPQ — enough to average out jitter without much lag.
    private var tickTimes: [TimeInterval] = []
    private static let bpmWindow: Int = 24
    /// Last BPM pushed to the engine. Guards against re-pushing the
    /// same (or near-same) value every tick.
    private var lastPushedBPM: BPM?
    private static let bpmChangeThreshold: Double = 0.5

    /// Returns nil if CoreMIDI client/port creation fails (rare on
    /// device; common on iOS simulator).
    public init?() {
        guard let helper = MIDIInputHelper() else { return nil }
        self.helper = helper
        helper.onMIDIByte = { [weak self] byte, time in
            // Real-time MIDI thread. Spawn a tiny Task to re-enter
            // actor isolation. Cost is a Task allocation per byte;
            // at 24 PPQ × 400 BPM that's ~160 Tasks/sec, well within
            // Swift concurrency's tolerance.
            Task { [weak self] in
                await self?.processByte(byte, at: time)
            }
        }
    }

    /// Wire this receiver to the engine it drives.
    public func bind(to engine: MetronomeEngine) {
        self.engineRef = engine
    }

    /// Toggle slave-mode listening. When off, incoming MIDI bytes are
    /// dropped without engine effects. When toggled off mid-stream, the
    /// tick window resets so the next "on" cycle starts fresh.
    public func setEnabled(_ enabled: Bool) {
        let wasEnabled = isEnabled
        isEnabled = enabled
        helper.isConnected = enabled
        if wasEnabled && !enabled {
            tickTimes.removeAll(keepingCapacity: true)
            lastPushedBPM = nil
        }
    }

    /// Restrict the receiver to a single named external source, or
    /// `nil` to listen to all of them (legacy behavior). The receiver
    /// reconnects in place when enabled; when disabled, the new filter
    /// is remembered and takes effect next time `setEnabled(true)` is
    /// called. Tick-window state is cleared so the BPM estimator
    /// doesn't carry stale inter-tick deltas across sources.
    public func setSelectedSource(name: String?) {
        helper.selectedSourceName = name
        if isEnabled {
            // Bounce the connection so the new filter applies. Reusing
            // the toggle path keeps connect/disconnect bookkeeping in
            // one place.
            helper.isConnected = false
            helper.isConnected = true
        }
        tickTimes.removeAll(keepingCapacity: true)
        lastPushedBPM = nil
    }

    /// Snapshot of currently-available external MIDI source display
    /// names, in CoreMIDI enumeration order, with the meter-gnome send
    /// source filtered out. Returned for the Settings picker UI; the
    /// caller can refresh by calling again. Empty when CoreMIDI reports
    /// no external sources (common on simulator).
    public func availableSources() -> [String] {
        helper.availableSourceNames()
    }

    // MARK: - Byte processing

    private func processByte(_ byte: UInt8, at time: TimeInterval) async {
        guard isEnabled, let engine = engineRef else { return }

        switch byte {
        case 0xF8: // MIDI Timing Clock
            recordTick(at: time)
            if let bpm = computedBPM() {
                await pushBPMIfChanged(bpm, to: engine)
            }
        case 0xFA: // MIDI Start
            // Reset the window so the BPM computation starts from this
            // moment forward — incoming Clock immediately after Start is
            // the most reliable signal.
            tickTimes.removeAll(keepingCapacity: true)
            lastPushedBPM = nil
            await engine.start()
        case 0xFB: // MIDI Continue
            // Treat like Start when not paused; resume if paused.
            let isPaused = await engine.isPaused
            if isPaused {
                await engine.resume()
            } else {
                await engine.start()
            }
        case 0xFC: // MIDI Stop
            await engine.stop()
            tickTimes.removeAll(keepingCapacity: true)
            lastPushedBPM = nil
        default:
            // Active Sensing (0xFE), Reset (0xFF), channel messages,
            // SysEx — ignore.
            break
        }
    }

    // MARK: - BPM tracking

    private func recordTick(at time: TimeInterval) {
        tickTimes.append(time)
        if tickTimes.count > Self.bpmWindow {
            tickTimes.removeFirst(tickTimes.count - Self.bpmWindow)
        }
    }

    /// Computes BPM from the current tick window, or `nil` if the window
    /// isn't full enough yet (< 4 ticks ≈ < 1/6 beat — too noisy).
    private func computedBPM() -> BPM? {
        guard tickTimes.count >= 4,
              let first = tickTimes.first,
              let last = tickTimes.last
        else { return nil }
        let intervals = tickTimes.count - 1
        let avgTickPeriod = (last - first) / Double(intervals)
        guard avgTickPeriod > 0 else { return nil }
        let beatPeriod = avgTickPeriod * 24
        return BPM(60.0 / beatPeriod)
    }

    private func pushBPMIfChanged(_ bpm: BPM, to engine: MetronomeEngine) async {
        if let last = lastPushedBPM,
           abs(last.value - bpm.value) < Self.bpmChangeThreshold {
            return
        }
        lastPushedBPM = bpm
        await engine.setBPM(bpm)
    }
}

/// Non-actor helper that owns the CoreMIDI client + input port and the
/// read block. Stays a class (not actor) because CoreMIDI's input
/// callback is delivered on a real-time MIDI thread, where actor
/// re-entry would be both costly and unnecessary — we just forward
/// each byte through a closure and let the actor do the actual work.
private final class MIDIInputHelper {
    /// `var`-with-default rather than `let` so the closure passed to
    /// `MIDIInputPortCreateWithBlock` can capture `self` before all
    /// stored properties are assigned — the compiler otherwise rejects
    /// the closure with "used before being initialized." Deinit's
    /// zero-check handles the never-set case for failed init paths.
    var client: MIDIClientRef = 0
    var port: MIDIPortRef = 0

    /// Callback fired for each MIDI byte received. `time` is the engine
    /// clock's `now` at packet-arrival time.
    var onMIDIByte: ((UInt8, TimeInterval) -> Void)?

    /// When set true, connects to all current MIDI sources (excluding
    /// our own "meter-gnome" send output). When false, disconnects.
    var isConnected: Bool = false {
        didSet {
            if isConnected && !oldValue { connectMatchingSources() }
            if !isConnected && oldValue { disconnectAllSources() }
        }
    }

    /// Optional source-name filter. `nil` = connect to every external
    /// source (legacy behavior). A name = connect only to sources whose
    /// CoreMIDI `kMIDIPropertyName` matches exactly. Mutated by the
    /// owning `MIDIReceiver` via `setSelectedSource(name:)`; the
    /// receiver bounces `isConnected` to re-evaluate the filter.
    var selectedSourceName: String? = nil

    private var connectedSources: [MIDIEndpointRef] = []
    private let clock = SystemClock()

    init?() {
        var clientRef = MIDIClientRef()
        let cs = MIDIClientCreate("meter-gnome-rx" as CFString, nil, nil, &clientRef)
        guard cs == noErr else {
            print("MIDIReceiver: MIDIClientCreate failed (\(cs))")
            return nil
        }
        self.client = clientRef

        var portRef = MIDIPortRef()
        let ps = MIDIInputPortCreateWithBlock(
            clientRef,
            "meter-gnome-rx-port" as CFString,
            &portRef
        ) { [weak self] packetListPtr, _ in
            self?.handlePackets(packetListPtr)
        }
        guard ps == noErr else {
            print("MIDIReceiver: MIDIInputPortCreateWithBlock failed (\(ps))")
            MIDIClientDispose(clientRef)
            return nil
        }
        self.port = portRef
    }

    deinit {
        for src in connectedSources {
            MIDIPortDisconnectSource(port, src)
        }
        if port != 0 { MIDIPortDispose(port) }
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: - Source management

    /// Connect to external sources, honoring `selectedSourceName`. When
    /// it's nil, connects to every source except our own "meter-gnome"
    /// send output (legacy behavior). When it's a name, connects only
    /// to sources whose CoreMIDI name matches exactly — used by the
    /// Settings → MIDI source picker to isolate one master out of many.
    private func connectMatchingSources() {
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let src = MIDIGetSource(i)
            let name = sourceName(src)
            // Skip our own output endpoint to avoid feedback when both
            // send + receive are enabled.
            guard name != "meter-gnome" else { continue }
            if let selected = selectedSourceName, name != selected { continue }
            if MIDIPortConnectSource(port, src, nil) == noErr {
                connectedSources.append(src)
            }
        }
    }

    private func disconnectAllSources() {
        for src in connectedSources {
            MIDIPortDisconnectSource(port, src)
        }
        connectedSources.removeAll(keepingCapacity: true)
    }

    /// CoreMIDI display name for an endpoint, or empty string if it
    /// has no name property (shouldn't happen for real devices). Used
    /// for both the own-source guard and the picker source listing.
    private func sourceName(_ source: MIDIEndpointRef) -> String {
        var nameProp: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(source, kMIDIPropertyName, &nameProp) == noErr
        else { return "" }
        return nameProp?.takeRetainedValue() as String? ?? ""
    }

    /// All external source names CoreMIDI currently reports, minus our
    /// own "meter-gnome" send output. Duplicates are deliberately kept
    /// (two sources with the same name are real — e.g., USB MIDI cable
    /// + network session both publishing the same device).
    func availableSourceNames() -> [String] {
        let count = MIDIGetNumberOfSources()
        var names: [String] = []
        for i in 0..<count {
            let src = MIDIGetSource(i)
            let name = sourceName(src)
            guard !name.isEmpty, name != "meter-gnome" else { continue }
            names.append(name)
        }
        return names
    }

    // MARK: - Packet decoding

    private func handlePackets(_ packetListPtr: UnsafePointer<MIDIPacketList>) {
        let now = clock.now  // capture arrival time once per packet list
        let list = packetListPtr.pointee
        var packet = list.packet
        for _ in 0..<Int(list.numPackets) {
            let length = Int(packet.length)
            withUnsafePointer(to: packet.data) { tuplePtr in
                tuplePtr.withMemoryRebound(to: UInt8.self, capacity: length) { bytes in
                    for i in 0..<length {
                        onMIDIByte?(bytes[i], now)
                    }
                }
            }
            packet = withUnsafeMutablePointer(to: &packet) {
                MIDIPacketNext($0).pointee
            }
        }
    }
}
