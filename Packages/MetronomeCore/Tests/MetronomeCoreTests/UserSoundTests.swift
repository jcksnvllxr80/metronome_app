import Testing
import Foundation
@testable import MetronomeCore

// MARK: - UserSound value type

@Test func userSoundClampsVolumeTrimAboveOne() {
    let s = UserSound(name: "Shaker", filename: "abc.caf", volumeTrim: 1.5)
    #expect(s.volumeTrim == 1.0)
}

@Test func userSoundClampsVolumeTrimBelowZero() {
    let s = UserSound(name: "Shaker", filename: "abc.caf", volumeTrim: -0.2)
    #expect(s.volumeTrim == 0.0)
}

@Test func userSoundPresetKeyRoundTrip() {
    let id = UUID()
    let s = UserSound(id: id, name: "Cabasa", filename: "cabasa.wav")
    let key = s.soundPresetKey
    #expect(key.hasPrefix("user:"))
    #expect(UserSound.id(fromKey: key) == id)
}

@Test func presetKeyReturnsNilForBuiltinSound() {
    // ClickSound.rawValue strings should NOT decode to a UUID — that
    // keeps the resolution chain in AudioScheduler safe to fall through
    // when the key is a built-in.
    #expect(UserSound.id(fromKey: ClickSound.woodBlock.rawValue) == nil)
    #expect(UserSound.id(fromKey: "digitalBeep") == nil)
    #expect(UserSound.id(fromKey: "") == nil)
}

@Test func presetKeyReturnsNilForMalformedKey() {
    #expect(UserSound.id(fromKey: "user:not-a-uuid") == nil)
    #expect(UserSound.id(fromKey: "User:\(UUID().uuidString)") == nil)  // case sensitive
}

@Test func userSoundCodableRoundTrip() throws {
    let original = UserSound(
        name: "Tabla",
        filename: "tabla.aif",
        volumeTrim: 0.65
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(UserSound.self, from: data)
    #expect(decoded == original)
}

// MARK: - Limits

@Test func limitsAreSpec() {
    #expect(UserSoundLimits.maxDurationSeconds == 2.0)
    #expect(UserSoundLimits.maxFileSizeBytes == 1_048_576)  // 1 MiB
}
