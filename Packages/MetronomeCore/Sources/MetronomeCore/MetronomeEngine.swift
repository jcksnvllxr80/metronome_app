import Foundation

/// Central engine class per spec §17 / CLAUDE.md Architecture.
///
/// Owns the mutable state (BPM, time signature, subdivision, running flag)
/// and — in a later commit — the `AVAudioEngine`. Runs on its own actor
/// isolation. Explicitly NOT `@MainActor` so the audio scheduler doesn't
/// contend with UI work.
///
/// This file contains the skeleton only — no audio, no AVFoundation. The
/// scheduling math lives in `ClickSchedule`, which is pure and testable
/// with `FakeClock`. The audio integration lands once the host app has
/// a real signal path.
public actor MetronomeEngine {
    private let clock: any EngineClock

    public private(set) var bpm: BPM
    public private(set) var timeSignature: TimeSignature
    public private(set) var subdivision: Subdivision
    public private(set) var isRunning: Bool = false
    public private(set) var schedule: ClickSchedule?

    public init(
        clock: any EngineClock = SystemClock(),
        bpm: BPM = BPM(120),
        timeSignature: TimeSignature = .fourFour,
        subdivision: Subdivision = .none
    ) {
        self.clock = clock
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.subdivision = subdivision
    }

    /// Anchor a new click sequence at `clock.now` and mark running.
    public func start() {
        schedule = ClickSchedule(
            bpm: bpm,
            timeSignature: timeSignature,
            subdivision: subdivision,
            startTime: clock.now
        )
        isRunning = true
    }

    /// Stop emitting clicks. The schedule is cleared; `start()` re-anchors.
    public func stop() {
        isRunning = false
        schedule = nil
    }

    /// Change tempo. If running, the click sequence re-anchors at `clock.now`
    /// (the next click fires immediately). Preserving the existing beat phase
    /// across a tempo change is more accurate but adds complexity; for the
    /// skeleton we accept re-anchor and revisit when wiring tempo automation
    /// (spec §6.3).
    public func setBPM(_ newBPM: BPM) {
        bpm = newBPM
        reanchorIfRunning()
    }

    public func setTimeSignature(_ newTS: TimeSignature) {
        timeSignature = newTS
        reanchorIfRunning()
    }

    public func setSubdivision(_ newSub: Subdivision) {
        subdivision = newSub
        reanchorIfRunning()
    }

    /// Next `count` clicks starting at or after `clock.now`. Returns `[]`
    /// when the engine is stopped. Callers (the audio scheduler) keep
    /// 4–8 beats queued per spec §1.2.
    public func upcomingClicks(count: Int) -> [Click] {
        guard isRunning, let schedule else { return [] }
        return schedule.clicks(from: clock.now, count: count)
    }

    private func reanchorIfRunning() {
        guard isRunning else { return }
        schedule = ClickSchedule(
            bpm: bpm,
            timeSignature: timeSignature,
            subdivision: subdivision,
            startTime: clock.now
        )
    }
}
