import Foundation

/// Central engine class per spec §17 / CLAUDE.md Architecture.
///
/// Owns the mutable state (BPM, time signature, subdivision, accent pattern,
/// settings, running flag) and the attached `AudioScheduler`. Runs on its
/// own actor isolation. Explicitly NOT `@MainActor` so the audio scheduler
/// doesn't contend with UI work.
///
/// The scheduling math lives in `ClickSchedule`, which is pure and testable
/// with `FakeClock`. Audio output goes through `AudioScheduler` (sub-commit
/// B onward). When no scheduler is attached, the engine is fully functional
/// in silent mode — the visual pulse still drives off `upcomingClicks(count:)`.
public actor MetronomeEngine {
    private let clock: any EngineClock

    public private(set) var bpm: BPM
    public private(set) var timeSignature: TimeSignature
    public private(set) var subdivision: Subdivision
    public private(set) var accentPattern: AccentPattern?
    public private(set) var settings: EngineSettings
    public private(set) var isRunning: Bool = false
    /// `true` when the engine was paused by an audio-session interruption
    /// or route change and is waiting on `resume()`. Mutually exclusive with
    /// `isRunning`. Set back to `false` by `stop()` (full reset) or by
    /// `resume()` (returns to running).
    public private(set) var isPaused: Bool = false
    public private(set) var schedule: ClickSchedule?

    /// Audio output sink. `nil` when running silently (engine math still
    /// works; the Stage UI's visual pulse still pulses).
    public private(set) var scheduler: AudioScheduler?

    public init(
        clock: any EngineClock = SystemClock(),
        bpm: BPM = BPM(120),
        timeSignature: TimeSignature = .fourFour,
        subdivision: Subdivision = .none,
        accentPattern: AccentPattern? = nil,
        settings: EngineSettings = EngineSettings()
    ) {
        self.clock = clock
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.subdivision = subdivision
        self.settings = settings
        if let pattern = accentPattern, pattern.timeSignature == timeSignature {
            self.accentPattern = pattern
        } else {
            self.accentPattern = nil
        }
    }

    /// Anchor a new click sequence at `clock.now` and mark running. When an
    /// audio scheduler is attached, also starts audio playback.
    ///
    /// `countIn` overrides `settings.countIn` for this start. When `nil`,
    /// the engine uses its persisted setting.
    public func start(countIn: CountIn? = nil) async {
        let effective = countIn ?? settings.countIn
        rebuildSchedule(countIn: effective)
        isRunning = true
        isPaused = false
        if let scheduler {
            await scheduler.start(engine: self)
        }
    }

    /// Stop emitting clicks. The schedule is cleared; audio (if attached)
    /// is torn down.
    public func stop() async {
        isRunning = false
        isPaused = false
        schedule = nil
        if let scheduler {
            await scheduler.stop()
        }
    }

    /// Pause playback without tearing down the audio engine. Used for
    /// audio-session interruptions (phone calls, Siri) and route changes
    /// (headphone unplug). The schedule is preserved so `resume()` can
    /// re-anchor at `clock.now` without losing user intent. No-op when
    /// not running.
    public func pause() async {
        guard isRunning else { return }
        isRunning = false
        isPaused = true
        // Schedule stays — resume() will re-anchor it.
        if let scheduler {
            await scheduler.pause()
        }
    }

    /// Resume after a `pause()`. Re-anchors the click sequence at `clock.now`
    /// (no count-in — this is a continuation, not a new start). No-op when
    /// not paused. Called by the audio session coordinator when an
    /// interruption ends with `.shouldResume` AND
    /// `settings.autoResumeAfterInterruption` is true, OR manually by the
    /// user pressing Play.
    public func resume() async {
        guard isPaused else { return }
        rebuildSchedule(countIn: .off)
        isRunning = true
        isPaused = false
        if let scheduler {
            await scheduler.resume(engine: self)
        }
    }

    /// Change tempo. Re-anchors the click sequence at `clock.now` when running.
    public func setBPM(_ newBPM: BPM) {
        bpm = newBPM
        reanchorIfRunning()
    }

    /// Change time signature. If the active accent pattern was scoped to the
    /// old time signature, it is cleared (per spec §3.2 / CLAUDE.md).
    public func setTimeSignature(_ newTS: TimeSignature) {
        timeSignature = newTS
        if let pattern = accentPattern, pattern.timeSignature != newTS {
            accentPattern = nil
        }
        reanchorIfRunning()
    }

    public func setSubdivision(_ newSub: Subdivision) {
        subdivision = newSub
        reanchorIfRunning()
    }

    /// Set or clear the accent pattern. Returns `true` if accepted; `false`
    /// if the pattern's time signature doesn't match the engine's current
    /// time signature. Passing `nil` always succeeds.
    @discardableResult
    public func setAccentPattern(_ pattern: AccentPattern?) -> Bool {
        if let pattern, pattern.timeSignature != timeSignature {
            return false
        }
        accentPattern = pattern
        reanchorIfRunning()
        return true
    }

    /// Replace the engine's settings wholesale.
    public func setSettings(_ newSettings: EngineSettings) {
        settings = newSettings
    }

    /// Attach an `AudioScheduler` for audio output. The app target builds
    /// the scheduler (which owns `AVAudioEngine`) and hands it in. Pass
    /// `nil` to detach (silent mode).
    public func attach(scheduler: AudioScheduler?) {
        self.scheduler = scheduler
    }

    /// Next `count` clicks starting at or after `clock.now`. Returns `[]`
    /// when the engine is stopped. The UI uses this to drive the visual
    /// pulse + active beat indicator.
    public func upcomingClicks(count: Int) -> [Click] {
        guard isRunning, let schedule else { return [] }
        return schedule.clicks(from: clock.now, count: count)
    }

    /// Clicks with `time > after`, up to `count`. Used by `AudioScheduler`
    /// to drive its refill loop — passing the last-scheduled click's time
    /// prevents re-scheduling clicks that are already in the player node's
    /// queue. Returns `[]` when stopped.
    public func clicks(after: TimeInterval, count: Int) -> [Click] {
        guard isRunning, let schedule else { return [] }
        // `firstClickIndex(atOrAfter:)` is inclusive; offset by a tiny
        // epsilon so a click at exactly `after` isn't returned again.
        let strict = after + 1e-9
        let startIdx = schedule.firstClickIndex(atOrAfter: strict)
        return (0..<count).map { schedule.click(at: startIdx + $0) }
    }

    // MARK: - Private

    private func rebuildSchedule(countIn: CountIn = .off) {
        schedule = ClickSchedule(
            bpm: bpm,
            timeSignature: timeSignature,
            subdivision: subdivision,
            startTime: clock.now,
            accentPattern: accentPattern,
            countInMeasures: countIn.measures
        )
    }

    private func reanchorIfRunning() {
        guard isRunning else { return }
        // Mid-run re-anchors never re-trigger count-in.
        rebuildSchedule(countIn: .off)
        // Notify the scheduler so it can flush its buffered queue and
        // refill from the new schedule. Fire-and-forget: capture the
        // scheduler reference, not self.
        if let scheduler {
            Task { [scheduler] in
                await scheduler.scheduleReset()
            }
        }
    }
}
