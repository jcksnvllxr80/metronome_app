import Testing
import Foundation
@testable import MetronomeCore

// MARK: - ClickSchedule count-in math

@Test func scheduleWithoutCountInDefaultsToZero() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    #expect(s.countInMeasures == 0)
    #expect(s.countInClicks == 0)
    #expect(s.click(at: 0).isCountIn == false)
}

@Test func countInClicksCountAccountsForSubdivision() {
    let s = ClickSchedule(
        bpm: BPM(120),
        timeSignature: .fourFour,
        subdivision: .eighth,
        startTime: 0,
        countInMeasures: 2
    )
    // 2 measures × 4 beats × 2 eighths = 16 count-in clicks
    #expect(s.countInClicks == 16)
}

@Test func countInClicksAreFlagged() {
    let s = ClickSchedule(
        bpm: BPM(120),
        timeSignature: .fourFour,
        subdivision: .none,
        startTime: 0,
        countInMeasures: 2
    )
    // First 8 clicks (2 measures × 4 beats) are count-in
    for i in 0..<8 { #expect(s.click(at: i).isCountIn) }
    // Click 8 is the actual downbeat of measure 0 of the song
    #expect(s.click(at: 8).isCountIn == false)
}

@Test func countInUsesDefaultAccentNotPattern() {
    // Pattern would normally mute beat 2 — but during count-in, every
    // downbeat should ACCENT and other beats should be NORMAL.
    let pattern = AccentPattern(
        name: "x",
        timeSignature: .fourFour,
        beats: [BeatConfig(accent: .accent), BeatConfig(accent: .mute), BeatConfig(accent: .mute), BeatConfig(accent: .mute)]
    )!
    let s = ClickSchedule(
        bpm: BPM(120),
        timeSignature: .fourFour,
        subdivision: .none,
        startTime: 0,
        accentPattern: pattern,
        countInMeasures: 1
    )
    // Count-in: downbeat is .accent, others .normal — pattern ignored
    #expect(s.click(at: 0).accent == .accent)
    #expect(s.click(at: 1).accent == .normal)
    #expect(s.click(at: 2).accent == .normal)
    #expect(s.click(at: 3).accent == .normal)
    // After count-in, pattern kicks in
    #expect(s.click(at: 4).accent == .accent)
    #expect(s.click(at: 5).accent == .mute)
    #expect(s.click(at: 6).accent == .mute)
    #expect(s.click(at: 7).accent == .mute)
}

@Test func countInMeasureIndexResetsForSong() {
    let s = ClickSchedule(
        bpm: BPM(120),
        timeSignature: .fourFour,
        subdivision: .none,
        startTime: 0,
        countInMeasures: 2
    )
    // During count-in: measure 0 then measure 1
    #expect(s.click(at: 0).measureIndex == 0)
    #expect(s.click(at: 4).measureIndex == 1)
    // First click of the actual song should be measure 0 of the song
    #expect(s.click(at: 8).measureIndex == 0)
    #expect(s.click(at: 8).isDownbeat)
}

@Test func countInClicksHaveCorrectTimings() {
    // At 120 BPM, click period is 0.5s. 4 count-in clicks land at 0, 0.5, 1, 1.5.
    let s = ClickSchedule(
        bpm: BPM(120),
        timeSignature: .fourFour,
        subdivision: .none,
        startTime: 10.0,
        countInMeasures: 1
    )
    #expect(s.click(at: 0).time == 10.0)
    #expect(s.click(at: 3).time == 11.5)
    #expect(s.click(at: 4).time == 12.0)
}

// MARK: - Engine integration

@Test func engineStartHonorsSettingsCountIn() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(
        clock: clock,
        bpm: BPM(120),
        settings: EngineSettings(countIn: .twoMeasures)
    )
    await engine.start()
    let clicks = await engine.upcomingClicks(count: 10)
    // 2 measures × 4 beats = 8 count-in clicks
    for i in 0..<8 { #expect(clicks[i].isCountIn) }
    #expect(clicks[8].isCountIn == false)
    #expect(clicks[8].isDownbeat)
}

@Test func engineStartCountInOverrideWins() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(
        clock: clock,
        settings: EngineSettings(countIn: .fourMeasures)
    )
    // Override to .off for setlist auto-advance scenario
    await engine.start(countIn: .off)
    let clicks = await engine.upcomingClicks(count: 1)
    #expect(clicks[0].isCountIn == false)
    #expect(clicks[0].isDownbeat)
}

@Test func midRunReanchorDoesNotRetriggerCountIn() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(
        clock: clock,
        settings: EngineSettings(countIn: .oneMeasure)
    )
    await engine.start()
    let beforeBPM = await engine.upcomingClicks(count: 1).first!
    #expect(beforeBPM.isCountIn) // count-in is happening

    // User changes tempo — re-anchor must NOT re-trigger count-in
    await engine.setBPM(BPM(180))
    let afterBPM = await engine.upcomingClicks(count: 1).first!
    #expect(afterBPM.isCountIn == false)
}

@Test func engineSettingsRoundTrip() async {
    let engine = MetronomeEngine(clock: FakeClock())
    let custom = EngineSettings(
        masterVolume: 0.7,
        latencyOffsetSeconds: -0.020,
        mixWithOthers: false,
        countIn: .twoMeasures,
        bpmPrecisionMode: true
    )
    await engine.setSettings(custom)
    let stored = await engine.settings
    #expect(stored == custom)
}
