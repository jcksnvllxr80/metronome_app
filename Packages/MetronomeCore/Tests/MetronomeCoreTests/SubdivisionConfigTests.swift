import Testing
import Foundation
@testable import MetronomeCore

// MARK: - Per-subdivision-level click configuration (spec §2.3)

@Test func legacyConfigIsSoftAccentNoOverride() {
    let cfg = SubdivisionConfig.legacy
    #expect(cfg.accent == .soft)
    #expect(cfg.soundOverride == nil)
}

@Test func subdivisionClickUsesLegacyDefaultWhenConfigNil() {
    // Schedule built without subdivisionConfig — every subdivision click
    // should use the pre-spec-§2.3 hardcoded behavior (`.soft`, nil).
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .eighth,
        startTime: 0, subdivisionConfig: nil
    )
    let mainClick = s.click(at: 0)   // beat 0, sub 0 — downbeat
    let subClick = s.click(at: 1)    // beat 0, sub 1 — the "and"
    #expect(subClick.subdivisionIndex == 1)
    #expect(subClick.accent == .soft, "legacy default for sub click")
    #expect(subClick.soundOverride == nil, "legacy default — inherit parent")
    // Downbeat shouldn't be affected by the subdivision config either way.
    #expect(mainClick.subdivisionIndex == 0)
}

@Test func subdivisionClickAccentRespectsConfig() {
    let cfg = SubdivisionConfig(accent: .normal, soundOverride: nil)
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .eighth,
        startTime: 0, subdivisionConfig: cfg
    )
    let subClick = s.click(at: 1)
    #expect(subClick.subdivisionIndex == 1)
    #expect(subClick.accent == .normal, "sub click follows config accent")
}

@Test func subdivisionClickSoundOverrideRespectsConfig() {
    let cfg = SubdivisionConfig(accent: .soft, soundOverride: "woodBlock")
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .triplet,
        startTime: 0, subdivisionConfig: cfg
    )
    let sub1 = s.click(at: 1) // first triplet partial
    let sub2 = s.click(at: 2) // second triplet partial
    #expect(sub1.soundOverride == "woodBlock")
    #expect(sub2.soundOverride == "woodBlock")
}

@Test func subdivisionConfigDoesNotAffectMainBeats() {
    // The config is for non-zero subdivisionIndex only — main beats keep
    // their accent-pattern / default behavior. Sanity-check that loud sub
    // accent + override doesn't bleed into beat 0.
    let cfg = SubdivisionConfig(accent: .accent, soundOverride: "woodBlock")
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .eighth,
        startTime: 0, subdivisionConfig: cfg
    )
    let downbeat = s.click(at: 0)
    let beat2 = s.click(at: 2) // beat 1, sub 0
    #expect(downbeat.subdivisionIndex == 0)
    #expect(downbeat.soundOverride == nil, "main beats ignore sub config")
    #expect(beat2.subdivisionIndex == 0)
    #expect(beat2.soundOverride == nil)
}

@Test func countInSubdivisionsIgnoreConfig() {
    // Count-in clicks always get the clean preamble (legacy default) —
    // even when the user has configured loud subdivisions for the main
    // song. Keeps the count-in audibly distinct from the song proper.
    let cfg = SubdivisionConfig(accent: .accent, soundOverride: "woodBlock")
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .eighth,
        startTime: 0, countInMeasures: 1, subdivisionConfig: cfg
    )
    // First measure (8 clicks at eighth subdivision) is count-in.
    let countInSub = s.click(at: 1) // count-in beat 0, sub 1
    #expect(countInSub.isCountIn)
    #expect(countInSub.accent == .soft, "count-in subs stay on the legacy default")
    #expect(countInSub.soundOverride == nil)
    // First sub click AFTER count-in should follow the config.
    let songSub = s.click(at: 9) // song beat 0, sub 1
    #expect(!songSub.isCountIn)
    #expect(songSub.accent == .accent)
    #expect(songSub.soundOverride == "woodBlock")
}

@Test func engineSettingsPlumbsConfigToSchedule() async {
    let settings = EngineSettings(
        subdivisionConfigs: [.eighth: SubdivisionConfig(accent: .loud, soundOverride: "clave")]
    )
    let engine = MetronomeEngine(clock: FakeClock(), bpm: BPM(120))
    await engine.setSettings(settings)
    await engine.setSubdivision(.eighth)
    await engine.start()
    let schedule = await engine.schedule
    guard let s = schedule else { Issue.record("no schedule"); return }
    let subClick = s.click(at: 1)
    #expect(subClick.accent == .loud, "engine pulled config from settings")
    #expect(subClick.soundOverride == "clave")
}

@Test func engineSettingsConfigDoesNotApplyToDifferentSubdivision() async {
    // Settings entry is for .eighth only; switching to .triplet should
    // fall back to legacy until the user configures triplets too.
    let settings = EngineSettings(
        subdivisionConfigs: [.eighth: SubdivisionConfig(accent: .loud, soundOverride: "clave")]
    )
    let engine = MetronomeEngine(clock: FakeClock(), bpm: BPM(120))
    await engine.setSettings(settings)
    await engine.setSubdivision(.triplet)
    await engine.start()
    let schedule = await engine.schedule
    guard let s = schedule else { Issue.record("no schedule"); return }
    let subClick = s.click(at: 1)
    #expect(subClick.accent == .soft, "triplet has no entry — legacy default")
    #expect(subClick.soundOverride == nil)
}

@Test func settingsConfigRoundTripsThroughCodable() throws {
    let original = EngineSettings(
        subdivisionConfigs: [
            .eighth: SubdivisionConfig(accent: .normal, soundOverride: nil),
            .triplet: SubdivisionConfig(accent: .loud, soundOverride: "woodBlock"),
        ]
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(EngineSettings.self, from: data)
    #expect(decoded.subdivisionConfigs[.eighth]?.accent == .normal)
    #expect(decoded.subdivisionConfigs[.triplet]?.soundOverride == "woodBlock")
}

@Test func legacySettingsJSONDecodesWithEmptyConfigMap() throws {
    // Pre-feature JSON has no subdivisionConfigs field — must decode as
    // an empty map so all existing users get legacy behavior on upgrade.
    let legacyJSON = """
    {"masterVolume": 1.0, "latencyOffsetSeconds": 0, "mixWithOthers": true, "countIn": 0, "bpmPrecisionMode": false, "autoResumeAfterInterruption": false, "clickSound": "digitalBeep", "midiClockEnabled": false, "midiClockReceiveEnabled": false, "voiceCountMode": "off", "randomMutePercentage": 0, "hapticMode": "off", "keepScreenAwakeDuringPlayback": true, "startOnLaunch": false, "dailyPracticeGoalMinutes": 0}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(EngineSettings.self, from: legacyJSON)
    #expect(decoded.subdivisionConfigs.isEmpty)
}
