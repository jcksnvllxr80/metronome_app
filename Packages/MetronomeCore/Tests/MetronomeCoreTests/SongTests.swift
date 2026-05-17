import Testing
import Foundation
@testable import MetronomeCore

// MARK: - SongDuration

@Test func songDurationCasesEqualByValue() {
    #expect(SongDuration.measures(8) == SongDuration.measures(8))
    #expect(SongDuration.measures(8) != SongDuration.measures(16))
    #expect(SongDuration.seconds(30) == SongDuration.seconds(30))
    #expect(SongDuration.measures(8) != SongDuration.seconds(8))
}

// MARK: - Song construction

@Test func minimalSongConstructs() throws {
    let song = try #require(Song(title: "Test", bpm: BPM(120)))
    #expect(song.title == "Test")
    #expect(song.bpm == BPM(120))
    #expect(song.timeSignature == .fourFour)
    #expect(song.subdivision == .none)
    #expect(song.accentPattern == nil)
    #expect(song.soundPreset == nil)
    #expect(song.notes == nil)
    #expect(song.duration == nil)
}

@Test func songRejectsMismatchedAccentPattern() {
    let pattern = AccentPattern.standard(for: .sevenEight)
    let song = Song(title: "X", bpm: BPM(120), timeSignature: .fourFour, accentPattern: pattern)
    #expect(song == nil)
}

@Test func songAcceptsMatchingAccentPattern() throws {
    let pattern = AccentPattern.standard(for: .threeFour)
    let song = try #require(Song(
        title: "Waltz",
        bpm: BPM(150),
        timeSignature: .threeFour,
        accentPattern: pattern
    ))
    #expect(song.accentPattern?.name == "Standard")
}

@Test func songIdIsStable() throws {
    let id = UUID()
    let song = try #require(Song(id: id, title: "X", bpm: BPM(120)))
    #expect(song.id == id)
}

@Test func songCarriesAllFields() throws {
    let song = try #require(Song(
        title: "Wonderwall",
        bpm: BPM(87),
        timeSignature: .fourFour,
        subdivision: .eighth,
        soundPreset: "acoustic-click",
        notes: "Capo 2",
        duration: .measures(64)
    ))
    #expect(song.subdivision == .eighth)
    #expect(song.soundPreset == "acoustic-click")
    #expect(song.notes == "Capo 2")
    #expect(song.duration == .measures(64))
}

// MARK: - Song mutation

@Test func setAccentPatternAcceptsMatching() throws {
    var song = try #require(Song(title: "X", bpm: BPM(120), timeSignature: .fourFour))
    let pattern = AccentPattern.standard(for: .fourFour)
    let accepted = song.setAccentPattern(pattern)
    #expect(accepted == true)
    #expect(song.accentPattern?.name == "Standard")
}

@Test func setAccentPatternRejectsMismatching() throws {
    var song = try #require(Song(title: "X", bpm: BPM(120), timeSignature: .fourFour))
    let pattern = AccentPattern.standard(for: .sevenEight)
    let accepted = song.setAccentPattern(pattern)
    #expect(accepted == false)
    #expect(song.accentPattern == nil)
}

@Test func setTimeSignatureClearsMismatchedPattern() throws {
    var song = try #require(Song(
        title: "X",
        bpm: BPM(120),
        timeSignature: .fourFour,
        accentPattern: AccentPattern.standard(for: .fourFour)
    ))
    #expect(song.accentPattern != nil)
    song.setTimeSignature(.threeFour)
    #expect(song.timeSignature == .threeFour)
    #expect(song.accentPattern == nil)
}

@Test func setTimeSignatureKeepsMatchingPattern() throws {
    var song = try #require(Song(
        title: "X",
        bpm: BPM(120),
        timeSignature: .fourFour,
        accentPattern: AccentPattern.standard(for: .fourFour)
    ))
    song.setTimeSignature(.fourFour) // same
    #expect(song.accentPattern != nil)
}

// MARK: - Engine integration

@Test func engineApplySongLoadsAllFields() async throws {
    let pattern = AccentPattern.standard(for: .sevenEight)
    let song = try #require(Song(
        title: "Money",
        bpm: BPM(150),
        timeSignature: .sevenEight,
        subdivision: .triplet,
        accentPattern: pattern
    ))
    let engine = MetronomeEngine(clock: FakeClock())
    await engine.apply(song)
    let bpm = await engine.bpm
    let ts = await engine.timeSignature
    let sub = await engine.subdivision
    let active = await engine.accentPattern
    #expect(bpm == BPM(150))
    #expect(ts == .sevenEight)
    #expect(sub == .triplet)
    #expect(active?.timeSignature == .sevenEight)
}

@Test func engineApplySongFromDifferentTimeSig() async throws {
    // Engine starts in 4/4, song is in 7/8. apply() must update TS BEFORE
    // pattern, otherwise the pattern would be rejected as mismatched.
    let pattern = AccentPattern.standard(for: .sevenEight)
    let song = try #require(Song(
        title: "Odd",
        bpm: BPM(140),
        timeSignature: .sevenEight,
        accentPattern: pattern
    ))
    let engine = MetronomeEngine(clock: FakeClock(), timeSignature: .fourFour)
    await engine.apply(song)
    let active = await engine.accentPattern
    #expect(active != nil)
    #expect(active?.timeSignature == .sevenEight)
}

@Test func engineApplySongWhileRunningReanchors() async throws {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    clock.advance(by: 0.3)
    let song = try #require(Song(title: "Slow", bpm: BPM(60)))
    await engine.apply(song)
    let clicks = await engine.upcomingClicks(count: 2)
    let reanchorLeadIn = MetronomeEngine.reanchorLeadInSeconds
    // New schedule anchors at clock.now + reanchor lead-in (0.3 + 0.06),
    // with new period = 1.0. Tolerance accounts for floating-point
    // compound-add precision at the second click.
    #expect(abs(clicks[0].time - (0.3 + reanchorLeadIn)) < 1e-9)
    #expect(abs(clicks[1].time - (1.3 + reanchorLeadIn)) < 1e-9)
}
