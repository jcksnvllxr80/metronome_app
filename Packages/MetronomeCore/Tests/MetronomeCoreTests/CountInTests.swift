import Testing
@testable import MetronomeCore

@Test func countInMeasuresMatchRawValue() {
    #expect(CountIn.off.measures == 0)
    #expect(CountIn.oneMeasure.measures == 1)
    #expect(CountIn.twoMeasures.measures == 2)
    #expect(CountIn.fourMeasures.measures == 4)
}

@Test func countInIsActiveFlag() {
    #expect(CountIn.off.isActive == false)
    #expect(CountIn.oneMeasure.isActive)
    #expect(CountIn.twoMeasures.isActive)
    #expect(CountIn.fourMeasures.isActive)
}

@Test func countInAllCasesIsClosedList() {
    // Spec is explicit: only those four options. If someone adds a 3-measure
    // case, this test fails and forces a spec/UX conversation.
    #expect(CountIn.allCases.count == 4)
}

// MARK: - EngineSettings

@Test func engineSettingsDefaults() {
    let s = EngineSettings()
    #expect(s.masterVolume == 1.0)
    #expect(s.latencyOffsetSeconds == 0)
    // Default flipped to false in v0.32.5 so fresh installs claim
    // Now Playing (lock-screen / Control Center card). User can flip
    // it back on in Settings → Playback Behavior for tuner coexistence.
    #expect(s.mixWithOthers == false)
    #expect(s.countIn == .off)
    #expect(s.bpmPrecisionMode == false)
}

@Test func engineSettingsClampsVolume() {
    #expect(EngineSettings(masterVolume: -1).masterVolume == 0)
    #expect(EngineSettings(masterVolume: 2).masterVolume == 1)
    #expect(EngineSettings(masterVolume: 0.5).masterVolume == 0.5)
}

@Test func engineSettingsClampsLatency() {
    #expect(EngineSettings(latencyOffsetSeconds: -1).latencyOffsetSeconds == -0.050)
    #expect(EngineSettings(latencyOffsetSeconds: 1).latencyOffsetSeconds == 0.050)
    #expect(EngineSettings(latencyOffsetSeconds: 0.025).latencyOffsetSeconds == 0.025)
}
