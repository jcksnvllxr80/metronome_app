//
//  MetronomeViewModel.swift
//  meter-gnome
//
//  Bridges the off-main `MetronomeEngine` actor to SwiftUI's @MainActor
//  Observation world. Holds a snapshot of engine state for synchronous
//  view reads, and forwards user actions into the engine via Task awaits.
//

import SwiftUI
import MetronomeCore

@Observable
final class MetronomeViewModel {
    let engine: MetronomeEngine

    // Mirrored engine state. Updated synchronously when SwiftUI sends an
    // action (optimistic), then reconciled from the engine via refresh().
    var bpm: BPM = BPM(120)
    var timeSignature: TimeSignature = .fourFour
    var subdivision: Subdivision = .none
    var isRunning: Bool = false

    init(engine: MetronomeEngine = MetronomeEngine()) {
        self.engine = engine
        Task { await self.refresh() }
    }

    /// Pull the authoritative state off the engine actor. Cheap (single
    /// actor hop) and idempotent — safe to call after any mutation.
    func refresh() async {
        let bpm = await engine.bpm
        let ts = await engine.timeSignature
        let sub = await engine.subdivision
        let running = await engine.isRunning
        self.bpm = bpm
        self.timeSignature = ts
        self.subdivision = sub
        self.isRunning = running
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
}
