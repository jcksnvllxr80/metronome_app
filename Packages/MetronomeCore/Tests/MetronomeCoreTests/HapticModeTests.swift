import Testing
import Foundation
@testable import MetronomeCore

private func click(beat: Int, sub: Int, accent: AccentLevel, isCountIn: Bool = false) -> Click {
    Click(
        beatIndex: beat,
        subdivisionIndex: sub,
        measureIndex: 0,
        time: 0,
        accent: accent,
        soundOverride: nil,
        pitchShift: .unison,
        isCountIn: isCountIn
    )
}

@Test func hapticOffNeverFires() {
    for accent in AccentLevel.allCases {
        #expect(!HapticMode.off.shouldFire(for: click(beat: 0, sub: 0, accent: accent)))
    }
}

@Test func hapticDownbeatOnlyFiresOnFirstBeatOnly() {
    #expect(HapticMode.downbeatOnly.shouldFire(for: click(beat: 0, sub: 0, accent: .accent)))
    #expect(!HapticMode.downbeatOnly.shouldFire(for: click(beat: 1, sub: 0, accent: .accent)))
    #expect(!HapticMode.downbeatOnly.shouldFire(for: click(beat: 0, sub: 1, accent: .soft)))
}

@Test func hapticAccentsOnlyFiresOnAccentLevel() {
    #expect(HapticMode.accentsOnly.shouldFire(for: click(beat: 2, sub: 0, accent: .accent)))
    #expect(!HapticMode.accentsOnly.shouldFire(for: click(beat: 2, sub: 0, accent: .loud)))
    #expect(!HapticMode.accentsOnly.shouldFire(for: click(beat: 2, sub: 0, accent: .normal)))
    // Subdivision clicks never fire under accents-only.
    #expect(!HapticMode.accentsOnly.shouldFire(for: click(beat: 2, sub: 1, accent: .accent)))
}

@Test func hapticEveryBeatFiresOnMainBeatsExceptMuted() {
    #expect(HapticMode.everyBeat.shouldFire(for: click(beat: 0, sub: 0, accent: .accent)))
    #expect(HapticMode.everyBeat.shouldFire(for: click(beat: 1, sub: 0, accent: .normal)))
    #expect(HapticMode.everyBeat.shouldFire(for: click(beat: 2, sub: 0, accent: .soft)))
    // Muted beats stay quiet.
    #expect(!HapticMode.everyBeat.shouldFire(for: click(beat: 1, sub: 0, accent: .mute)))
    // Subdivisions don't fire.
    #expect(!HapticMode.everyBeat.shouldFire(for: click(beat: 1, sub: 1, accent: .soft)))
}

@Test func hapticSubdivisionsTooFiresOnEveryNonMuteClick() {
    #expect(HapticMode.subdivisionsToo.shouldFire(for: click(beat: 0, sub: 0, accent: .accent)))
    #expect(HapticMode.subdivisionsToo.shouldFire(for: click(beat: 1, sub: 2, accent: .soft)))
    #expect(!HapticMode.subdivisionsToo.shouldFire(for: click(beat: 1, sub: 1, accent: .mute)))
}

@Test func hapticModeCodableRoundTrip() throws {
    for mode in HapticMode.allCases {
        let data = try JSONEncoder().encode(mode)
        let back = try JSONDecoder().decode(HapticMode.self, from: data)
        #expect(back == mode)
    }
}

@Test func engineSettingsCarriesHapticMode() {
    let settings = EngineSettings(hapticMode: .everyBeat)
    #expect(settings.hapticMode == .everyBeat)
    let defaultSettings = EngineSettings()
    #expect(defaultSettings.hapticMode == .off)
}
