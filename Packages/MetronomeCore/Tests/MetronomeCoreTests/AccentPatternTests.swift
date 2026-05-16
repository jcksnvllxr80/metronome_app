import Testing
@testable import MetronomeCore

// MARK: - PitchShift

@Test func pitchShiftSemitones() {
    #expect(PitchShift.octaveDown.semitones == -12)
    #expect(PitchShift.unison.semitones == 0)
    #expect(PitchShift.octaveUp.semitones == 12)
}

// MARK: - BeatConfig

@Test func beatConfigDefaultsToNormalUnison() {
    let cfg = BeatConfig()
    #expect(cfg.accent == .normal)
    #expect(cfg.soundOverride == nil)
    #expect(cfg.pitchShift == .unison)
}

@Test func beatConfigConveniencePresets() {
    #expect(BeatConfig.downbeat.accent == .accent)
    #expect(BeatConfig.mainBeat.accent == .normal)
    #expect(BeatConfig.muted.accent == .mute)
}

// MARK: - AccentPattern construction

@Test func patternRejectsWrongLengthBeats() {
    let beats: [BeatConfig] = [.downbeat, .mainBeat]
    let pattern = AccentPattern(name: "bad", timeSignature: .fourFour, beats: beats)
    #expect(pattern == nil)
}

@Test func patternAcceptsMatchingLength() {
    let beats: [BeatConfig] = [.downbeat, .mainBeat, .mainBeat, .mainBeat]
    let pattern = AccentPattern(name: "ok", timeSignature: .fourFour, beats: beats)
    #expect(pattern != nil)
    #expect(pattern?.beats.count == 4)
}

@Test func standardPatternForFourFour() {
    let p = AccentPattern.standard(for: .fourFour)
    #expect(p.beats.count == 4)
    #expect(p.beats[0].accent == .accent)
    #expect(p.beats[1].accent == .normal)
    #expect(p.beats[2].accent == .normal)
    #expect(p.beats[3].accent == .normal)
}

@Test func standardPatternForOddMeter() {
    let p = AccentPattern.standard(for: .sevenEight)
    #expect(p.beats.count == 7)
    #expect(p.beats[0].accent == .accent)
    for i in 1..<7 { #expect(p.beats[i].accent == .normal) }
}

@Test func patternConfigWrapsBeatIndex() {
    let p = AccentPattern.standard(for: .fourFour)
    #expect(p.config(forBeat: 0).accent == .accent)
    #expect(p.config(forBeat: 4).accent == .accent) // wraps
    #expect(p.config(forBeat: 5).accent == .normal)
}

// MARK: - ClickSchedule with pattern

@Test func scheduleAppliesPatternAccents() {
    let beats: [BeatConfig] = [
        BeatConfig(accent: .accent),
        BeatConfig(accent: .mute),
        BeatConfig(accent: .loud),
        BeatConfig(accent: .soft),
    ]
    let pattern = AccentPattern(name: "custom", timeSignature: .fourFour, beats: beats)!
    let s = ClickSchedule(
        bpm: BPM(120),
        timeSignature: .fourFour,
        subdivision: .none,
        startTime: 0,
        accentPattern: pattern
    )
    #expect(s.click(at: 0).accent == .accent)
    #expect(s.click(at: 1).accent == .mute)
    #expect(s.click(at: 2).accent == .loud)
    #expect(s.click(at: 3).accent == .soft)
    // Wraps to next measure
    #expect(s.click(at: 4).accent == .accent)
}

@Test func sceduleAppliesPatternSoundAndPitch() {
    let beats: [BeatConfig] = [
        BeatConfig(accent: .accent, soundOverride: "cowbell", pitchShift: .octaveUp),
        BeatConfig(accent: .normal),
        BeatConfig(accent: .normal, soundOverride: "rim", pitchShift: .octaveDown),
        BeatConfig(accent: .normal),
    ]
    let pattern = AccentPattern(name: "drumrack", timeSignature: .fourFour, beats: beats)!
    let s = ClickSchedule(
        bpm: BPM(120),
        timeSignature: .fourFour,
        subdivision: .none,
        startTime: 0,
        accentPattern: pattern
    )
    #expect(s.click(at: 0).soundOverride == "cowbell")
    #expect(s.click(at: 0).pitchShift == .octaveUp)
    #expect(s.click(at: 1).soundOverride == nil)
    #expect(s.click(at: 1).pitchShift == .unison)
    #expect(s.click(at: 2).soundOverride == "rim")
    #expect(s.click(at: 2).pitchShift == .octaveDown)
}

@Test func subdivisionsDoNotInheritParentBeatOverrides() {
    let beats: [BeatConfig] = [
        BeatConfig(accent: .accent, soundOverride: "cowbell", pitchShift: .octaveUp),
        BeatConfig(accent: .normal),
        BeatConfig(accent: .normal),
        BeatConfig(accent: .normal),
    ]
    let pattern = AccentPattern(name: "x", timeSignature: .fourFour, beats: beats)!
    let s = ClickSchedule(
        bpm: BPM(120),
        timeSignature: .fourFour,
        subdivision: .eighth,
        startTime: 0,
        accentPattern: pattern
    )
    // Click 0 is downbeat — gets the pattern's overrides
    let down = s.click(at: 0)
    #expect(down.accent == .accent)
    #expect(down.soundOverride == "cowbell")
    #expect(down.pitchShift == .octaveUp)
    // Click 1 is the eighth-note subdivision of beat 0 — must NOT inherit
    let sub = s.click(at: 1)
    #expect(sub.subdivisionIndex == 1)
    #expect(sub.accent == .soft)
    #expect(sub.soundOverride == nil)
    #expect(sub.pitchShift == .unison)
}

@Test func scheduleWithoutPatternFallsBackToDefault() {
    let s = ClickSchedule(
        bpm: BPM(120),
        timeSignature: .fourFour,
        subdivision: .none,
        startTime: 0
    )
    #expect(s.click(at: 0).accent == .accent)
    #expect(s.click(at: 1).accent == .normal)
    #expect(s.click(at: 0).soundOverride == nil)
    #expect(s.click(at: 0).pitchShift == .unison)
}

// MARK: - MetronomeEngine integration

@Test func enginePatternRejectedWhenTimeSignatureMismatches() async {
    let engine = MetronomeEngine(clock: FakeClock(), timeSignature: .fourFour)
    let badPattern = AccentPattern.standard(for: .sevenEight)
    let accepted = await engine.setAccentPattern(badPattern)
    #expect(accepted == false)
    let active = await engine.accentPattern
    #expect(active == nil)
}

@Test func enginePatternAcceptedWhenTimeSignatureMatches() async {
    let engine = MetronomeEngine(clock: FakeClock(), timeSignature: .fourFour)
    let pattern = AccentPattern.standard(for: .fourFour)
    let accepted = await engine.setAccentPattern(pattern)
    #expect(accepted == true)
    let active = await engine.accentPattern
    #expect(active?.name == "Standard")
}

@Test func engineClearsPatternOnTimeSignatureChange() async {
    let engine = MetronomeEngine(clock: FakeClock(), timeSignature: .fourFour)
    await engine.setAccentPattern(AccentPattern.standard(for: .fourFour))
    let before = await engine.accentPattern
    #expect(before != nil)

    await engine.setTimeSignature(.threeFour)
    let after = await engine.accentPattern
    #expect(after == nil)
}

@Test func engineKeepsPatternIfTimeSignatureUnchanged() async {
    let engine = MetronomeEngine(clock: FakeClock(), timeSignature: .fourFour)
    await engine.setAccentPattern(AccentPattern.standard(for: .fourFour))
    await engine.setTimeSignature(.fourFour) // same
    let after = await engine.accentPattern
    #expect(after != nil)
}

@Test func enginePatternFlowsIntoUpcomingClicks() async {
    let clock = FakeClock()
    let pattern = AccentPattern(
        name: "rock",
        timeSignature: .fourFour,
        beats: [
            BeatConfig(accent: .accent),
            BeatConfig(accent: .mute),
            BeatConfig(accent: .loud),
            BeatConfig(accent: .mute),
        ]
    )!
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120), timeSignature: .fourFour)
    await engine.setAccentPattern(pattern)
    await engine.start()
    let clicks = await engine.upcomingClicks(count: 4)
    #expect(clicks[0].accent == .accent)
    #expect(clicks[1].accent == .mute)
    #expect(clicks[2].accent == .loud)
    #expect(clicks[3].accent == .mute)
}

@Test func engineInitIgnoresMismatchedPattern() async {
    let pattern = AccentPattern.standard(for: .sevenEight)
    let engine = MetronomeEngine(
        clock: FakeClock(),
        timeSignature: .fourFour,
        accentPattern: pattern
    )
    let active = await engine.accentPattern
    #expect(active == nil)
}
