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

    /// Minimum number of clicks in the player node's pre-scheduled queue
    /// (spec §1.2 floor of 4). Adaptive policy: lookahead = max(4,
    /// ceil(minLookaheadSeconds / clickPeriod)) so at 400 BPM (period
    /// 150 ms) we queue ~4 clicks worth of audio (~600 ms), and at slow
    /// tempos we never queue MORE than necessary — keeps tempo-change
    /// latency bounded.
    private static let minLookaheadClicks: Int = 4
    private static let minLookaheadSeconds: TimeInterval = 0.5

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

    /// Light teardown for interruption / route-change pauses. Cancels the
    /// refill task and stops the player node, but keeps `AVAudioEngine`
    /// running and the session active so `resume(engine:)` can pick up
    /// quickly. The engine reference is held — `resume` re-uses it.
    public func pause() async {
        refillTask?.cancel()
        refillTask = nil
        playerNode.stop()
        playerNode.reset()
        lastScheduledTime = -.infinity
    }

    /// Pair to `pause()`. Re-attaches the engine reference and restarts
    /// the player node + refill loop. Faster than full `start(engine:)`
    /// because `AVAudioEngine` and the audio session stay live across
    /// the pause.
    public func resume(engine: MetronomeEngine) async {
        self.engineRef = engine
        lastScheduledTime = -.infinity
        if !avEngine.isRunning {
            do { try avEngine.start() }
            catch { print("AudioScheduler: avEngine.start failed on resume: \(error)") }
        }
        playerNode.play()
        refillTask?.cancel()
        refillTask = Task { [weak self] in
            await self?.refillLoop()
        }
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
        let lookahead = await adaptiveLookahead(for: engine)
        let upcoming = await engine.clicks(after: lastScheduledTime, count: lookahead)
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

    /// `max(4, ceil(0.5s / clickPeriod))` clicks. At 400 BPM (period
    /// 150 ms) → 4 clicks (~600 ms of audio queued); at 120 BPM (500 ms)
    /// → 4 clicks (~2 s); at 60 BPM (1000 ms) → 4 clicks (~4 s).
    /// At very slow tempos the floor of 4 keeps things stable; at fast
    /// tempos the seconds-floor would expand the queue, but realistically
    /// 4 clicks is already > 0.5 s for the whole audible tempo range with
    /// no subdivision. Subdivisions shrink clickPeriod and push lookahead up.
    private func adaptiveLookahead(for engine: MetronomeEngine) async -> Int {
        guard let schedule = await engine.schedule else {
            return Self.minLookaheadClicks
        }
        let bySeconds = Int(ceil(Self.minLookaheadSeconds / schedule.clickPeriod))
        return max(Self.minLookaheadClicks, bySeconds)
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
