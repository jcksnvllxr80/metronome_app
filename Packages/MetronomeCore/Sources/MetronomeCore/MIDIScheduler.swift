import Foundation
import CoreMIDI

/// Sends MIDI Clock (0xF8 at 24 PPQ) plus Start (0xFA) / Stop (0xFC)
/// real-time messages on a virtual MIDI source named "meter-gnome" so
/// DAWs and other MIDI-aware apps can slave to the metronome's tempo.
/// Spec §12.2.
///
/// Architecture parallels `AudioScheduler`: a refill loop on this actor
/// computes upcoming tick times from `engine.schedule` (BPM + startTime)
/// and schedules MIDI packets with `MIDITimeStamp` values derived from
/// `SystemClock.audioTime(forEngineTime:)`. Same `mach_absolute_time`
/// base as audio output, so MIDI ticks and audio clicks share one clock
/// — no drift between the metronome you hear and the DAW that's slaved.
///
/// Reception (slave mode) is deliberately out of scope here; that's a
/// separate flow and the spec marks it optional.
public actor MIDIScheduler {
    // MARK: - Constants

    /// MIDI real-time message bytes (single-byte, status 0xF0–0xFF).
    private static let midiTimingClock: UInt8 = 0xF8
    private static let midiStart: UInt8       = 0xFA
    private static let midiContinue: UInt8    = 0xFB
    private static let midiStop: UInt8        = 0xFC

    /// Pulses per quarter note — MIDI standard.
    private static let ppq: Int = 24

    /// Refill cadence. Loose enough that we're not burning CPU; tight
    /// enough that the lookahead queue stays well-fed even at 400 BPM
    /// (one tick every ~6 ms at 400 BPM, 48 ticks = ~300 ms).
    private static let refillIntervalMs: UInt64 = 100

    /// Ticks scheduled ahead per refill pass. 48 = 2 beats at any tempo.
    private static let lookaheadTicks: Int = 48

    // MARK: - State

    public let virtualSource: MIDIEndpointRef
    private let client: MIDIClientRef
    private let clock = SystemClock()

    private weak var engineRef: MetronomeEngine?
    private var refillTask: Task<Void, Never>?
    /// Index of the most recently scheduled tick since the current
    /// schedule's `startTime`. Reset by `scheduleReset()` and on stop().
    private var lastScheduledTick: Int = -1
    /// Tracks whether we've sent a MIDI Start that hasn't been balanced
    /// by a MIDI Stop yet. Prevents double-stops on tear-down paths.
    private var startSent: Bool = false
    private var isEnabled: Bool = false

    // MARK: - Lifecycle

    /// Construct the MIDI client + virtual source. Returns `nil` if the
    /// CoreMIDI calls fail (rare on real devices; simulator support is
    /// historically uneven). Callers should treat MIDI as optional —
    /// audio + visual pulse still work without it.
    public init?() {
        var clientRef = MIDIClientRef()
        let cs = MIDIClientCreate("meter-gnome" as CFString, nil, nil, &clientRef)
        guard cs == noErr else {
            print("MIDIScheduler: MIDIClientCreate failed (\(cs))")
            return nil
        }

        var sourceRef = MIDIEndpointRef()
        let ss = MIDISourceCreateWithProtocol(
            clientRef,
            "meter-gnome" as CFString,
            ._1_0,
            &sourceRef
        )
        guard ss == noErr else {
            print("MIDIScheduler: MIDISourceCreateWithProtocol failed (\(ss))")
            MIDIClientDispose(clientRef)
            return nil
        }

        self.client = clientRef
        self.virtualSource = sourceRef
    }

    deinit {
        // CoreMIDI's Dispose calls are thread-safe and don't await on
        // anything — safe to call from non-isolated actor deinit.
        if virtualSource != 0 { MIDIEndpointDispose(virtualSource) }
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: - Public control

    /// Toggle MIDI Clock output globally. When `false`, `start(engine:)`
    /// no-ops; when toggled `false` mid-play, the refill loop stops
    /// scheduling new ticks. The virtual source stays visible to other
    /// apps either way (creating + destroying the source on every toggle
    /// is more visible churn than just gating the output).
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// Send MIDI Start + begin scheduling Clock ticks. No-op when
    /// `isEnabled` is false.
    public func start(engine: MetronomeEngine) async {
        self.engineRef = engine
        guard isEnabled else { return }
        lastScheduledTick = -1
        sendRealTime(byte: Self.midiStart)
        startSent = true
        refillTask?.cancel()
        refillTask = Task { [weak self] in
            await self?.refillLoop()
        }
    }

    /// Send MIDI Stop, cancel the refill task, clear state.
    public func stop() async {
        refillTask?.cancel()
        refillTask = nil
        if startSent {
            sendRealTime(byte: Self.midiStop)
            startSent = false
        }
        lastScheduledTick = -1
        engineRef = nil
    }

    /// Engine calls this when its schedule rebuilds (BPM / time-sig /
    /// subdivision change). Drops the tick counter so the refill loop
    /// re-anchors against the new `schedule.startTime`. Does NOT send
    /// MIDI Stop/Start — slaved DAWs prefer continuous Clock over Start
    /// nukes on every tempo tweak.
    public func scheduleReset() async {
        lastScheduledTick = -1
    }

    // MARK: - Refill loop

    private func refillLoop() async {
        while !Task.isCancelled {
            await refillOnce()
            try? await Task.sleep(nanoseconds: Self.refillIntervalMs * 1_000_000)
        }
    }

    private func refillOnce() async {
        guard isEnabled, let engine = engineRef else { return }
        let isRunning = await engine.isRunning
        guard isRunning, let schedule = await engine.schedule else { return }

        let tickPeriod = (60.0 / schedule.bpm.value) / Double(Self.ppq)
        let startTime = schedule.startTime
        let now = clock.now

        // The first tick to schedule is the max of:
        //  - one after our last-scheduled index (linear progression), and
        //  - the first tick that hasn't yet passed in real time (catches
        //    cases where we missed a refill window).
        let nextFromCounter = lastScheduledTick + 1
        let firstUnpassed = max(0, Int(ceil((now - startTime) / tickPeriod)))
        let firstIndex = max(nextFromCounter, firstUnpassed)

        for tickIdx in firstIndex..<(firstIndex + Self.lookaheadTicks) {
            let tickTime = startTime + Double(tickIdx) * tickPeriod
            let hostTime = clock.audioTime(forEngineTime: tickTime).hostTime
            sendRealTime(byte: Self.midiTimingClock, at: hostTime)
            lastScheduledTick = tickIdx
        }
    }

    // MARK: - MIDI byte emission

    /// Send a one-byte real-time MIDI message. Defaults to "fire now";
    /// pass a `hostTime` to schedule precisely.
    private func sendRealTime(byte: UInt8, at hostTime: MIDITimeStamp = 0) {
        var packet = MIDIPacket()
        packet.timeStamp = hostTime  // 0 means "as soon as possible"
        packet.length = 1
        packet.data.0 = byte

        var packetList = MIDIPacketList(numPackets: 1, packet: packet)
        let status = MIDIReceived(virtualSource, &packetList)
        if status != noErr {
            // CoreMIDI errors on every packet is too noisy; log once.
            // For Phase 1 we just drop the log.
        }
    }
}
