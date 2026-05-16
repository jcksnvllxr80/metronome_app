import Foundation

/// Central engine class per spec §17 / CLAUDE.md Architecture.
///
/// Owns the mutable state (BPM, time signature, subdivision, accent pattern,
/// running flag) and — in a later commit — the `AVAudioEngine`. Runs on its
/// own actor isolation. Explicitly NOT `@MainActor` so the audio scheduler
/// doesn't contend with UI work.
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
    public private(set) var accentPattern: AccentPattern?
    public private(set) var isRunning: Bool = false
    public private(set) var schedule: ClickSchedule?

    public init(
        clock: any EngineClock = SystemClock(),
        bpm: BPM = BPM(120),
        timeSignature: TimeSignature = .fourFour,
        subdivision: Subdivision = .none,
        accentPattern: AccentPattern? = nil
    ) {
        self.clock = clock
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.subdivision = subdivision
        // Ignore a pattern whose time signature doesn't match (avoid leaking
        // an invalid state out of init; user can call setAccentPattern later).
        if let pattern = accentPattern, pattern.timeSignature == timeSignature {
            self.accentPattern = pattern
        } else {
            self.accentPattern = nil
        }
    }

    /// Anchor a new click sequence at `clock.now` and mark running.
    public func start() {
        rebuildSchedule()
        isRunning = true
    }

    /// Stop emitting clicks. The schedule is cleared; `start()` re-anchors.
    public func stop() {
        isRunning = false
        schedule = nil
    }

    /// Change tempo. Re-anchors the click sequence at `clock.now` when running.
    public func setBPM(_ newBPM: BPM) {
        bpm = newBPM
        reanchorIfRunning()
    }

    /// Change time signature. If the active accent pattern was scoped to the
    /// old time signature, it is cleared — patterns don't translate across
    /// meters (per spec §3.2 / CLAUDE.md).
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
    /// time signature. Passing `nil` always succeeds (reverts to the default
    /// downbeat-only accent).
    @discardableResult
    public func setAccentPattern(_ pattern: AccentPattern?) -> Bool {
        if let pattern, pattern.timeSignature != timeSignature {
            return false
        }
        accentPattern = pattern
        reanchorIfRunning()
        return true
    }

    /// Next `count` clicks starting at or after `clock.now`. Returns `[]`
    /// when the engine is stopped. Callers (the audio scheduler) keep
    /// 4–8 beats queued per spec §1.2.
    public func upcomingClicks(count: Int) -> [Click] {
        guard isRunning, let schedule else { return [] }
        return schedule.clicks(from: clock.now, count: count)
    }

    // MARK: - Private

    private func rebuildSchedule() {
        schedule = ClickSchedule(
            bpm: bpm,
            timeSignature: timeSignature,
            subdivision: subdivision,
            startTime: clock.now,
            accentPattern: accentPattern
        )
    }

    private func reanchorIfRunning() {
        guard isRunning else { return }
        rebuildSchedule()
    }
}
