//
//  MetronomeViewModel.swift
//  meter-gnome
//
//  Bridges the off-main `MetronomeEngine` actor to SwiftUI's @MainActor
//  Observation world. Holds a snapshot of engine state for synchronous
//  view reads (BPM, time sig, current schedule), exposes pulse-intensity
//  + current-beat + tap-flash helpers for the live UI, and forwards user
//  actions into the engine via Task awaits.
//

import SwiftUI
import MetronomeCore

@Observable
final class MetronomeViewModel {
    let engine: MetronomeEngine

    /// Persistence handles. Optional so previews + tests can construct the
    /// view model with the engine alone (no SwiftData container needed).
    @ObservationIgnored let settingsStore: SettingsStore?
    @ObservationIgnored let libraryStore: LibraryStore?

    // Mirrored engine state. Optimistically updated on user action; the
    // authoritative read happens in refresh() right after.
    var bpm: BPM = BPM(120)
    var timeSignature: TimeSignature = .fourFour
    var subdivision: Subdivision = .none
    var isRunning: Bool = false
    var settings: EngineSettings = EngineSettings()
    /// A snapshot of the engine's current ClickSchedule. The view reads
    /// this every animation frame via TimelineView to drive the pulse.
    /// `nil` when the engine is stopped or before the first start().
    var schedule: ClickSchedule? = nil

    /// Clock time of the most recent tap on the tap-tempo button. Drives
    /// the visual flash via `tapFlashIntensity(at:)`. `-.infinity` means
    /// "never tapped" — by definition `time - (-.infinity) > 0.150`, so
    /// flash intensity reads 0.
    var lastTapTime: TimeInterval = -.infinity

    /// `@ObservationIgnored` because tap tempo state churns on every tap
    /// and re-rendering the whole view tree on each one is wasted work —
    /// the only output that should trigger a re-render is the resulting BPM,
    /// which already goes through the `bpm` field, plus the lastTapTime
    /// which is observed explicitly.
    @ObservationIgnored
    private var tapEstimator = TapTempoEstimator()

    init(
        engine: MetronomeEngine = MetronomeEngine(),
        settingsStore: SettingsStore? = nil,
        libraryStore: LibraryStore? = nil
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.libraryStore = libraryStore
        // Seed `settings` synchronously from the store if available so
        // the SettingsView opens with the persisted values, not defaults.
        if let initial = settingsStore?.current {
            self.settings = initial
        }
        Task { await self.refresh() }
    }

    /// Pull the authoritative state off the engine actor. Cheap (one actor
    /// hop) and idempotent — safe to call after any mutation.
    func refresh() async {
        let bpm = await engine.bpm
        let ts = await engine.timeSignature
        let sub = await engine.subdivision
        let running = await engine.isRunning
        let sched = await engine.schedule
        let settings = await engine.settings
        self.bpm = bpm
        self.timeSignature = ts
        self.subdivision = sub
        self.isRunning = running
        self.schedule = sched
        self.settings = settings
    }

    // MARK: - User actions

    func nudgeBPM(by delta: Double) {
        let newBPM = BPM(bpm.value + delta)
        bpm = newBPM // optimistic — engine clamps + snaps, refresh() reconciles
        Task {
            await engine.setBPM(newBPM)
            await refresh()
        }
    }

    func togglePlay() {
        Task {
            if await engine.isRunning {
                await engine.stop()
            } else {
                await engine.start()
            }
            await refresh()
        }
    }

    /// Commit a new time signature. The engine clears any accent pattern
    /// scoped to the old meter (per spec §3.2); refresh() picks that up.
    func setTimeSignature(_ newTS: TimeSignature) {
        timeSignature = newTS // optimistic
        Task {
            await engine.setTimeSignature(newTS)
            await refresh()
        }
    }

    /// Commit new engine settings. The audio scheduler picks up
    /// masterVolume / latencyOffsetSeconds at the next refill pass (~50 ms);
    /// countIn and autoResume apply at the next start / interruption.
    /// Persists to disk synchronously via SettingsStore so the change
    /// survives the next launch.
    func setSettings(_ newSettings: EngineSettings) {
        settings = newSettings // optimistic
        settingsStore?.update(newSettings)
        Task {
            await engine.setSettings(newSettings)
            await refresh()
        }
    }

    /// Register a tap from the UI's tap-tempo button. Always records
    /// `lastTapTime` so the flash fires even on a single tap (which by
    /// itself doesn't yet produce a BPM estimate).
    func tap() {
        let now = SystemClock().now
        lastTapTime = now
        guard let estimate = tapEstimator.tap(at: now) else { return }
        bpm = estimate
        Task {
            await engine.setBPM(estimate)
            await refresh()
        }
    }

    // MARK: - View helpers

    /// The most-recent click at or before `time`, or `nil` if no click has
    /// fired yet (engine stopped, or `time` is before the first click).
    func currentClick(at time: TimeInterval) -> Click? {
        guard let schedule, isRunning else { return nil }
        let nextIdx = schedule.firstClickIndex(atOrAfter: time)
        guard nextIdx > 0 else { return nil }
        return schedule.click(at: nextIdx - 1)
    }

    /// Pulse intensity [0, 1] at the given clock time. 1 = on accent peak,
    /// 0 = back to base color. Implements DESIGN.md's beat pulse spec:
    /// - 10 ms hard attack
    /// - `(60 / bpm) * 0.4` second ease-out decay (quadratic falloff)
    /// - Reduce Motion: discrete 30 ms hold of full intensity, no fade.
    func pulseIntensity(at time: TimeInterval, reduceMotion: Bool) -> Double {
        guard let click = currentClick(at: time) else { return 0 }
        let timeSince = time - click.time
        if timeSince < 0 { return 0 }

        if reduceMotion {
            return timeSince < 0.030 ? 1 : 0
        }

        let attack: TimeInterval = 0.010
        let decay = (60.0 / bpm.value) * 0.4
        if timeSince < attack { return 1 }
        if timeSince < attack + decay {
            let progress = (timeSince - attack) / decay
            // Ease-out from 1 → 0: y = (1 - x)^2. Falls fast initially, then settles.
            return (1 - progress) * (1 - progress)
        }
        return 0
    }

    /// Flash intensity [0, 1] for the tap-tempo button after a tap.
    /// 150 ms linear falloff — matches the "registered" feedback expected
    /// per spec §6.1.
    func tapFlashIntensity(at time: TimeInterval) -> Double {
        let elapsed = time - lastTapTime
        if elapsed < 0 || elapsed > 0.150 { return 0 }
        return max(0, 1 - elapsed / 0.150)
    }
}
