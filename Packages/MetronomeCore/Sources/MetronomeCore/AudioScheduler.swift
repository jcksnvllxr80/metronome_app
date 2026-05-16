import Foundation
import AVFoundation

#if canImport(UIKit)
import AVFAudio
#endif

/// Owns the `AVAudioEngine` and schedules click buffers ahead of the engine
/// clock. **Sub-commit B: first audible output.** Maintains a 4-click
/// lookahead via a refill loop. The engine pushes "schedule changed" events
/// (BPM / time-sig / accent edits) via `scheduleReset()`; the scheduler
/// flushes pending buffers and re-fills from the new schedule's `clock.now`.
///
/// Sub-commit C will: handle `AVAudioSession` interruptions + route changes,
/// adopt the Phase 1 sound library (replace `ClickBufferGenerator` with
/// real samples), make lookahead BPM-adaptive, and add `pause`/`resume`.
public actor AudioScheduler {
    /// Fraction of a second the refill loop sleeps between passes. 50 ms is
    /// well under one click period at the max tempo (60/400 = 150 ms), so
    /// the lookahead queue never drains.
    private static let refillIntervalMs: UInt64 = 50

    /// Number of clicks kept in the player node's pre-scheduled queue.
    /// 4 is the spec §1.2 floor; sub-commit C can make this BPM-adaptive
    /// (seconds-or-beats whichever-greater) per AUDIO_INTEGRATION_PLAN.md
    /// open question #2.
    private static let lookahead: Int = 4

    public let avEngine: AVAudioEngine
    public let playerNode: AVAudioPlayerNode
    public let format: AVAudioFormat

    private let clock = SystemClock()
    private var clickBuffers: [AccentLevel: AVAudioPCMBuffer] = [:]
    private weak var engineRef: MetronomeEngine?
    private var refillTask: Task<Void, Never>?
    /// The `EngineClock` time of the most recently scheduled click. Used
    /// to ask the engine only for clicks AFTER this point — prevents
    /// re-scheduling the same click on every refill pass.
    private var lastScheduledTime: TimeInterval = -.infinity

    public init() {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        self.avEngine = engine
        self.playerNode = node
        self.format = fmt

        // Pre-render one buffer per accent level.
        for level in AccentLevel.allCases {
            if let buf = ClickBufferGenerator.makeBuffer(format: fmt, accent: level) {
                clickBuffers[level] = buf
            }
        }
    }

    /// Activate the audio session, start the AVAudioEngine + player node,
    /// and begin the refill loop. Idempotent — calling on an already-
    /// running scheduler resets the lookahead queue.
    public func start(engine: MetronomeEngine) async {
        self.engineRef = engine
        lastScheduledTime = -.infinity

        activateSession()

        if !avEngine.isRunning {
            do { try avEngine.start() }
            catch { print("AudioScheduler: avEngine.start failed: \(error)") }
        }
        if !playerNode.isPlaying {
            playerNode.play()
        }

        refillTask?.cancel()
        refillTask = Task { [weak self] in
            await self?.refillLoop()
        }
    }

    /// Tear down audio output: cancel the refill task, stop the player and
    /// engine, deactivate the session. Buffers still queued in the player
    /// node are dropped.
    public func stop() async {
        refillTask?.cancel()
        refillTask = nil

        playerNode.stop()
        avEngine.stop()
        playerNode.reset()
        lastScheduledTime = -.infinity

        deactivateSession()
        engineRef = nil
    }

    /// Engine calls this when it rebuilds its schedule (BPM change, time
    /// signature change, etc.). Drops everything queued in the player node
    /// and lets the refill loop re-populate from the new schedule.
    public func scheduleReset() async {
        guard playerNode.isPlaying else { return }
        playerNode.reset()
        playerNode.play()
        lastScheduledTime = -.infinity
    }

    // MARK: - Refill loop

    private func refillLoop() async {
        while !Task.isCancelled {
            await refillOnce()
            try? await Task.sleep(nanoseconds: Self.refillIntervalMs * 1_000_000)
        }
    }

    private func refillOnce() async {
        guard let engine = engineRef else { return }
        let upcoming = await engine.clicks(after: lastScheduledTime, count: Self.lookahead)
        for click in upcoming {
            // Mute click: still advance `lastScheduledTime` so we don't
            // re-pull it next pass, but don't schedule anything audible.
            if click.accent == .mute {
                lastScheduledTime = click.time
                continue
            }
            guard let buffer = clickBuffers[click.accent] else { continue }
            let audioTime = clock.audioTime(forEngineTime: click.time)
            // Explicit `completionHandler: nil` selects the legacy sync
            // overload — the 2-arg form binds to an async variant in
            // recent SDKs that we don't want (awaiting it would block
            // the refill loop until the buffer finishes playing).
            playerNode.scheduleBuffer(buffer, at: audioTime, options: [], completionHandler: nil)
            lastScheduledTime = click.time
        }
    }

    // MARK: - Session activation (iOS only)

    private func activateSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioScheduler: session activate failed: \(error)")
        }
        #endif
    }

    private func deactivateSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        } catch {
            // Common during transitions; not worth surfacing.
        }
        #endif
    }
}
