//
//  MetronomeViewModel.swift
//  meter-gnome
//
//  Bridges the off-main `MetronomeEngine` actor to SwiftUI's @MainActor
//  Observation world. Holds a snapshot of engine state for synchronous
//  view reads (BPM, time sig, current schedule), exposes pulse-intensity
//  + current-beat helpers for the visual pulse, and forwards user actions
//  into the engine via Task awaits.
//

import SwiftUI
import MetronomeCore

@Observable
final class MetronomeViewModel {
    let engine: MetronomeEngine

    // Mirrored engine state. Optimistically updated on user action; the
    // authoritative read happens in refresh() right after.
    var bpm: BPM = BPM(120)
    var timeSignature: TimeSignature = .fourFour
    var subdivision: Subdivision = .none
    var isRunning: Bool = false
    /// A snapshot of the engine's current ClickSchedule. The view reads
    /// this every animation frame via TimelineView to drive the pulse.
    /// `nil` when the engine is stopped or before the first start().
    var schedule: ClickSchedule? = nil

    /// `@ObservationIgnored` because tap tempo state churns on every tap
    /// and re-rendering the whole view tree on each one is wasted work —
    /// the only output that should trigger a re-render is the resulting BPM,
    /// which already goes through the `bpm` field.
    @ObservationIgnored
    private var tapEstimator = TapTempoEstimator()

    init(engine: MetronomeEngine = MetronomeEngine()) {
        self.engine = engine
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
        self.bpm = bpm
        self.timeSignature = ts
        self.subdivision = sub
        self.isRunning = running
        self.schedule = sched
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

    /// Register a tap from the UI's tap-tempo button. The estimator times
    /// the gap to the previous tap and (after the second tap) pushes a fresh
    /// BPM estimate into the engine.
    func tap() {
        let now = SystemClock().now
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
}
