import Testing
import Foundation
@testable import MetronomeCore

// MARK: - Count-in routing through SongSectionPlayer (TODO §7.3 item)
//
// `SongSectionPlayer.play(_:countIn:)` forwards count-in to
// `engine.start(countIn:)` so multi-section songs in `.countdown` advance
// mode get a prelude before section 0 — matching flat-song behavior.
// The schedule's `countInClicks` is then used by tick()'s boundary math,
// so section 0's measure count still measures from the first SONG click,
// not from the count-in.

@Test func sectionPlayerPlayWithCountInBuildsCountInClicks() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SongSectionPlayer(engine: engine, clock: clock)
    let multi = Song(
        title: "M",
        bpm: BPM(120),
        sections: [
            SongSection(bpm: BPM(120), measureCount: 2)!,
            SongSection(bpm: BPM(80), measureCount: 2)!,
        ]
    )!

    await player.play(multi, countIn: .twoMeasures)

    let countInClicks = await engine.schedule?.countInClicks ?? -1
    let bpm = await engine.bpm
    let idx = await player.currentIndex
    let active = await player.isActive
    // Two measures of 4/4 = 8 count-in clicks.
    #expect(countInClicks == 8, "count-in routed through to engine.start")
    #expect(bpm == BPM(120), "section 0's BPM is loaded")
    #expect(idx == 0)
    #expect(active)
}

@Test func sectionBoundaryWaitsForCountInToComplete() async {
    // Section 0 is one measure at 60 BPM (= 4 seconds of song).
    // Count-in is two measures at 4/4 = 8 seconds of prelude.
    // Boundary should land at startTime + (countInClicks + measureCount *
    // clicksPerMeasure) * clickPeriod = startupLeadIn + 12 * 1.0 sec.
    // Advancing only past the count-in must NOT cross the boundary;
    // advancing past the full prelude + section must.
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SongSectionPlayer(engine: engine, clock: clock)
    let multi = Song(
        title: "M",
        bpm: BPM(60),
        sections: [
            SongSection(bpm: BPM(60), measureCount: 1)!,
            SongSection(bpm: BPM(60), measureCount: 1)!,
        ]
    )!

    await player.play(multi, countIn: .twoMeasures)
    let scheduleStart = await engine.schedule?.startTime ?? 0
    #expect(abs(scheduleStart - MetronomeEngine.startupLeadInSeconds) < 1e-9)

    // 5 seconds in: still inside the 8-second count-in prelude.
    clock.advance(by: 5)
    await player.tick()
    let idxMidCountIn = await player.currentIndex
    #expect(idxMidCountIn == 0, "Section 0 still active during count-in")

    // 4 more seconds (= 9 total): count-in done at 8.25, section 0 has
    // played for ~0.75 s of its 4-second measure. Still no advance.
    clock.advance(by: 4)
    await player.tick()
    let idxMidSection = await player.currentIndex
    #expect(idxMidSection == 0, "Section 0 still active mid-measure post-count-in")

    // 4 more seconds (= 13 total): past the boundary at ~12.19. Advance.
    clock.advance(by: 4)
    await player.tick()
    let idxAfter = await player.currentIndex
    let bpmAfter = await engine.bpm
    let countInAfter = await engine.schedule?.countInClicks ?? -1
    #expect(idxAfter == 1, "Section 1 active after count-in + section 0 elapsed")
    #expect(bpmAfter == BPM(60))
    #expect(countInAfter == 0, "Section transition reanchored without count-in")
}

@Test func sectionPlayerDefaultsToNoCountIn() async {
    // Existing callers that don't pass countIn keep the prior behavior:
    // no prelude, schedule starts immediately at section 0.
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SongSectionPlayer(engine: engine, clock: clock)
    let multi = Song(
        title: "M",
        bpm: BPM(100),
        sections: [
            SongSection(bpm: BPM(100), measureCount: 2)!,
            SongSection(bpm: BPM(140), measureCount: 2)!,
        ]
    )!
    await player.play(multi)
    let countIn = await engine.schedule?.countInClicks ?? -1
    #expect(countIn == 0, "Default play() doesn't introduce a count-in prelude")
}

// MARK: - SetlistPlayer routes count-in into multi-section advance

private func makeSong(_ title: String, bpm: Double, duration: SongDuration? = nil) -> Song {
    Song(title: title, bpm: BPM(bpm), duration: duration)!
}

@Test func setlistCountdownAdvanceIntoMultiSectionRoutesCountIn() async {
    // .countdown(measures: 1) → advancing from flat song A onto
    // multi-section song B should engage the section player with a
    // one-measure count-in prelude (vs. previous behavior: skipped).
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let sectionPlayer = SongSectionPlayer(engine: engine, clock: clock)
    let setlistPlayer = SetlistPlayer(engine: engine, sectionPlayer: sectionPlayer, clock: clock)

    let flat = makeSong("Flat", bpm: 60, duration: .seconds(5))
    let multi = Song(
        title: "Multi",
        bpm: BPM(120),
        sections: [
            SongSection(bpm: BPM(120), measureCount: 2)!,
            SongSection(bpm: BPM(80), measureCount: 2)!,
        ]
    )!
    let setlist = Setlist(name: "S", songs: [flat, multi], advanceMode: .countdown(measures: 1))

    await setlistPlayer.play(setlist)
    clock.advance(by: 6)
    await setlistPlayer.tick() // crosses .seconds(5) → .countdown advance

    let sectionActive = await sectionPlayer.isActive
    let engineBPM = await engine.bpm
    let countIn = await engine.schedule?.countInClicks ?? -1
    let setlistIdx = await setlistPlayer.currentIndex
    #expect(setlistIdx == 1, "Setlist advanced onto the multi-section song")
    #expect(sectionActive, "Multi-section routed through SongSectionPlayer")
    #expect(engineBPM == BPM(120), "Section 0's tempo loaded")
    // One measure of 4/4 at section 0's tempo = 4 count-in clicks.
    #expect(countIn == 4, "Count-in prelude was forwarded through to the engine")
}

@Test func setlistManualNextOntoMultiSectionSkipsCountIn() async {
    // Manual `next()` is intent-driven — skips count-in even when the
    // setlist's advanceMode would have one (mirrors flat-song behavior).
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let sectionPlayer = SongSectionPlayer(engine: engine, clock: clock)
    let setlistPlayer = SetlistPlayer(engine: engine, sectionPlayer: sectionPlayer, clock: clock)

    let flat = makeSong("Flat", bpm: 60)
    let multi = Song(
        title: "Multi",
        bpm: BPM(120),
        sections: [SongSection(bpm: BPM(120), measureCount: 2)!],
    )!
    let setlist = Setlist(name: "S", songs: [flat, multi], advanceMode: .countdown(measures: 2))

    await setlistPlayer.play(setlist)
    await setlistPlayer.next()

    let countIn = await engine.schedule?.countInClicks ?? -1
    let sectionActive = await sectionPlayer.isActive
    #expect(sectionActive, "Multi-section engaged on manual next")
    #expect(countIn == 0, "Manual advance skips count-in even on .countdown")
}
