import Testing
import Foundation
@testable import MetronomeCore

/// Test helper — constructs a Song with the given title, BPM, and optional
/// duration. Forced unwrap is safe (all inputs satisfy Song's invariants).
private func makeSong(_ title: String, bpm: Double, duration: SongDuration? = nil) -> Song {
    Song(title: title, bpm: BPM(bpm), duration: duration)!
}

// MARK: - Construction / empty cases

@Test func playerStartsInactive() async {
    let engine = MetronomeEngine(clock: FakeClock())
    let player = SetlistPlayer(engine: engine, clock: FakeClock())
    let active = await player.isActive
    let setlist = await player.setlist
    let idx = await player.currentIndex
    #expect(active == false)
    #expect(setlist == nil)
    #expect(idx == -1)
}

@Test func playingEmptySetlistIsNoop() async {
    let engine = MetronomeEngine(clock: FakeClock())
    let player = SetlistPlayer(engine: engine, clock: FakeClock())
    await player.play(Setlist(name: "Empty"))
    let active = await player.isActive
    #expect(active == false)
}

@Test func playLoadsFirstSongIntoEngine() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    let setlist = Setlist(name: "Set", songs: [
        makeSong("A", bpm: 90),
        makeSong("B", bpm: 140),
    ])
    await player.play(setlist)
    let engineBPM = await engine.bpm
    let engineRunning = await engine.isRunning
    let idx = await player.currentIndex
    #expect(engineBPM == BPM(90))
    #expect(engineRunning == true)
    #expect(idx == 0)
}

// MARK: - Manual advance

@Test func manualNextLoadsNextSong() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(Setlist(name: "Set", songs: [
        makeSong("A", bpm: 90),
        makeSong("B", bpm: 140),
    ]))
    await player.next()
    let bpm = await engine.bpm
    let idx = await player.currentIndex
    #expect(bpm == BPM(140))
    #expect(idx == 1)
}

@Test func manualPreviousLoadsPreviousSong() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(
        Setlist(name: "Set", songs: [makeSong("A", bpm: 90), makeSong("B", bpm: 140)]),
        startingAt: 1
    )
    await player.previous()
    let bpm = await engine.bpm
    let idx = await player.currentIndex
    #expect(bpm == BPM(90))
    #expect(idx == 0)
}

@Test func manualPreviousAtFirstSongIsNoop() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(Setlist(name: "Set", songs: [makeSong("A", bpm: 90)]))
    await player.previous()
    let idx = await player.currentIndex
    #expect(idx == 0)
}

@Test func manualNextAtLastSongStops() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(
        Setlist(name: "Set", songs: [makeSong("A", bpm: 90)])
    )
    await player.next()
    let active = await player.isActive
    let running = await engine.isRunning
    #expect(active == false)
    #expect(running == false)
}

// MARK: - Auto-advance via duration

@Test func nilDurationNeverAutoAdvances() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(Setlist(name: "Set", songs: [
        makeSong("A", bpm: 120),
        makeSong("B", bpm: 140),
    ], advanceMode: .immediate))

    // Simulate 60 seconds passing.
    clock.advance(by: 60)
    await player.tick()
    let idx = await player.currentIndex
    let bpm = await engine.bpm
    #expect(idx == 0)
    #expect(bpm == BPM(120))
}

@Test func secondsDurationAdvancesAfterElapsed() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(Setlist(name: "Set", songs: [
        makeSong("A", bpm: 120, duration: .seconds(10)),
        makeSong("B", bpm: 140),
    ], advanceMode: .immediate))

    // 5s elapsed — should NOT advance yet.
    clock.advance(by: 5)
    await player.tick()
    let idxMid = await player.currentIndex
    #expect(idxMid == 0)

    // 11s total elapsed — should have advanced.
    clock.advance(by: 6)
    await player.tick()
    let idxAfter = await player.currentIndex
    let bpmAfter = await engine.bpm
    #expect(idxAfter == 1)
    #expect(bpmAfter == BPM(140))
}

@Test func endOfSetlistStops() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(Setlist(name: "Set", songs: [
        makeSong("A", bpm: 120, duration: .seconds(5)),
    ], advanceMode: .immediate))
    clock.advance(by: 6)
    await player.tick()
    let active = await player.isActive
    let running = await engine.isRunning
    #expect(active == false)
    #expect(running == false)
}

// MARK: - Advance modes

@Test func immediateModeAdvancesWithoutGap() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(Setlist(name: "Set", songs: [
        makeSong("A", bpm: 120, duration: .seconds(10)),
        makeSong("B", bpm: 140),
    ], advanceMode: .immediate))
    clock.advance(by: 11)
    await player.tick()
    let running = await engine.isRunning
    #expect(running, "Engine should continue running in .immediate mode")
}

@Test func pauseModeStopsEngineAndWaits() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(Setlist(name: "Set", songs: [
        makeSong("A", bpm: 120, duration: .seconds(5)),
        makeSong("B", bpm: 140),
    ], advanceMode: .pause))
    clock.advance(by: 6)
    await player.tick()

    let active = await player.isActive
    let waiting = await player.isWaitingForResume
    let running = await engine.isRunning
    let bpm = await engine.bpm
    #expect(active, "Player stays active across .pause boundary")
    #expect(waiting, "Player is waiting for user to press Play")
    #expect(running == false, "Engine is stopped after .pause advance")
    #expect(bpm == BPM(140), "Next song's settings are loaded into the engine")
}

@Test func pauseModeResumesOnUserPlay() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(Setlist(name: "Set", songs: [
        makeSong("A", bpm: 120, duration: .seconds(5)),
        makeSong("B", bpm: 140, duration: .seconds(10)),
    ], advanceMode: .pause))
    clock.advance(by: 6)
    await player.tick()

    // User presses Play on Stage — engine starts (re-anchors at clock.now).
    await engine.start()
    await player.tick() // observe the transition
    let waiting = await player.isWaitingForResume
    #expect(waiting == false, "Resume detected; duration timer is now running")
}

@Test func countdownModeUsesCountIn() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(Setlist(name: "Set", songs: [
        makeSong("A", bpm: 120, duration: .seconds(5)),
        makeSong("B", bpm: 140),
    ], advanceMode: .countdown(measures: 1)))
    clock.advance(by: 6)
    await player.tick()

    // Engine should be running with count-in flagged on the next click.
    let upcoming = await engine.upcomingClicks(count: 1)
    let isCountIn = upcoming.first?.isCountIn ?? false
    let bpm = await engine.bpm
    #expect(bpm == BPM(140), "Engine is on song B's tempo during count-in")
    #expect(isCountIn, "First click after .countdown advance is a count-in click")
}

// MARK: - Stop

@Test func stopClearsAllState() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let player = SetlistPlayer(engine: engine, clock: clock)
    await player.play(Setlist(name: "Set", songs: [makeSong("A", bpm: 120)]))
    await player.stop()
    let active = await player.isActive
    let setlist = await player.setlist
    let idx = await player.currentIndex
    let running = await engine.isRunning
    #expect(active == false)
    #expect(setlist == nil)
    #expect(idx == -1)
    #expect(running == false)
}

// MARK: - Setlist × multi-section integration

/// Helper — builds a multi-section Song with the given (BPM, measures)
/// per section. All sections default to 4/4 time + .continue endAction.
private func makeMultiSectionSong(_ title: String, sections: [(Double, Int)]) -> Song {
    let songSections: [SongSection] = sections.map { (bpm, measures) in
        SongSection(bpm: BPM(bpm), measureCount: measures)!
    }
    return Song(title: title, bpm: BPM(sections.first?.0 ?? 120), sections: songSections)!
}

@Test func multiSectionSongInSetlistRoutesThroughSectionPlayer() async {
    // First song is multi-section — when the setlist starts, the section
    // player should be the one running, with the engine on section 0's
    // tempo (not the song's top-level fallback BPM).
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let sectionPlayer = SongSectionPlayer(engine: engine, clock: clock)
    let setlistPlayer = SetlistPlayer(engine: engine, sectionPlayer: sectionPlayer, clock: clock)

    let multi = makeMultiSectionSong("MultiA", sections: [(80, 2), (160, 2)])
    let flat = makeSong("FlatB", bpm: 100)
    let setlist = Setlist(name: "Set", songs: [multi, flat], advanceMode: .immediate)

    await setlistPlayer.play(setlist)

    let sectionActive = await sectionPlayer.isActive
    let engineBPM = await engine.bpm
    let engineRunning = await engine.isRunning
    #expect(sectionActive, "Multi-section song routes through SongSectionPlayer")
    #expect(engineBPM == BPM(80), "Engine BPM follows section 0, not song-level fallback")
    #expect(engineRunning)
}

@Test func multiSectionExhaustionAdvancesSetlistToNextSong() async {
    // Two-section first song → after all sections complete, the setlist
    // should advance to the second song (a flat song). The completion
    // callback path is what wires that transition.
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let sectionPlayer = SongSectionPlayer(engine: engine, clock: clock)
    let setlistPlayer = SetlistPlayer(engine: engine, sectionPlayer: sectionPlayer, clock: clock)

    // Two 1-measure sections at 60 BPM → 4 seconds per section, 8 total.
    let multi = makeMultiSectionSong("Multi", sections: [(60, 1), (60, 1)])
    let flat = makeSong("Flat", bpm: 150)
    let setlist = Setlist(name: "Set", songs: [multi, flat], advanceMode: .immediate)

    await setlistPlayer.play(setlist)
    // After play(): scheduled start = startupLeadIn (0.25s). Section 0's
    // boundary = startupLeadIn + 4s. Section 1's boundary = +4s after
    // its own reanchor at clock.now + reanchorLeadIn.
    //
    // Driving the section player's tick at section-boundary times to
    // simulate the live poll task. With FakeClock we just step forward
    // and call tick directly.
    clock.advance(by: 5)
    await sectionPlayer.tick()        // crosses section 0 → section 1
    clock.advance(by: 5)
    await sectionPlayer.tick()        // crosses section 1 → exhausted → callback fires

    let setlistIdx = await setlistPlayer.currentIndex
    let setlistSong = await setlistPlayer.currentSong
    let engineBPM = await engine.bpm
    #expect(setlistIdx == 1, "Setlist advanced past the multi-section song")
    #expect(setlistSong?.title == "Flat", "Now playing the second setlist entry")
    #expect(engineBPM == BPM(150), "Engine BPM follows the new flat song")
}

@Test func setlistStopAlsoStopsSectionPlayer() async {
    // When the user stops the setlist while a multi-section song is
    // playing, the section player must be torn down too — otherwise its
    // poll task keeps firing and the scheduling cap leaks into any later
    // non-section playback.
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    let sectionPlayer = SongSectionPlayer(engine: engine, clock: clock)
    let setlistPlayer = SetlistPlayer(engine: engine, sectionPlayer: sectionPlayer, clock: clock)

    let multi = makeMultiSectionSong("Multi", sections: [(90, 2), (120, 2)])
    await setlistPlayer.play(Setlist(name: "Set", songs: [multi], advanceMode: .immediate))
    await setlistPlayer.stop()

    let sectionActive = await sectionPlayer.isActive
    let engineRunning = await engine.isRunning
    #expect(sectionActive == false)
    #expect(engineRunning == false)
}
