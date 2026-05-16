import Testing
import Foundation
@testable import MetronomeCore

// Test helper — JSON round-trip
private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(value)
    return try decoder.decode(T.self, from: data)
}

// MARK: - Primitives

@Test func bpmRoundTrip() throws {
    let inputs = [BPM(40), BPM(120), BPM(120.5), BPM(400)]
    for bpm in inputs {
        let decoded = try roundTrip(bpm)
        #expect(decoded == bpm)
    }
}

@Test func bpmClampingOnDecodeOfOutOfRange() throws {
    // Hand-craft JSON with an out-of-range value; decode should clamp.
    let data = "500".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(BPM.self, from: data)
    #expect(decoded == BPM(BPM.maximum))
}

@Test func subdivisionRoundTrip() throws {
    for sub in Subdivision.allCases {
        let decoded = try roundTrip(sub)
        #expect(decoded == sub)
    }
}

@Test func subdivisionUsesStringRawValue() throws {
    let data = try JSONEncoder().encode(Subdivision.triplet)
    let str = String(data: data, encoding: .utf8)
    #expect(str == "\"triplet\"")
}

@Test func accentLevelRoundTrip() throws {
    for level in AccentLevel.allCases {
        #expect(try roundTrip(level) == level)
    }
}

@Test func pitchShiftRoundTrip() throws {
    for shift in PitchShift.allCases {
        #expect(try roundTrip(shift) == shift)
    }
}

@Test func countInRoundTrip() throws {
    for c in CountIn.allCases {
        #expect(try roundTrip(c) == c)
    }
}

@Test func timeSignatureRoundTrip() throws {
    let cases: [TimeSignature] = [.fourFour, .threeFour, .sevenEight, .twelveEight]
    for ts in cases {
        #expect(try roundTrip(ts) == ts)
    }
}

@Test func timeSignatureRejectsOutOfRangeOnDecode() throws {
    let json = #"{"numerator":99,"denominator":4}"#
    let data = json.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(TimeSignature.self, from: data)
    }
}

// MARK: - Composite types

@Test func beatConfigRoundTrip() throws {
    let cfg = BeatConfig(accent: .accent, soundOverride: "cowbell", pitchShift: .octaveUp)
    #expect(try roundTrip(cfg) == cfg)
}

@Test func accentPatternRoundTrip() throws {
    let pattern = AccentPattern.standard(for: .sevenEight)
    #expect(try roundTrip(pattern) == pattern)
}

@Test func accentPatternRejectsBeatCountMismatchOnDecode() throws {
    let json = #"{"name":"bad","timeSignature":{"numerator":4,"denominator":4},"beats":[{"accent":2,"pitchShift":0}]}"#
    let data = json.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(AccentPattern.self, from: data)
    }
}

@Test func songDurationMeasuresRoundTrip() throws {
    #expect(try roundTrip(SongDuration.measures(32)) == .measures(32))
}

@Test func songDurationSecondsRoundTrip() throws {
    #expect(try roundTrip(SongDuration.seconds(45.5)) == .seconds(45.5))
}

@Test func setlistAdvanceModeRoundTrip() throws {
    #expect(try roundTrip(SetlistAdvanceMode.pause) == .pause)
    #expect(try roundTrip(SetlistAdvanceMode.immediate) == .immediate)
    #expect(try roundTrip(SetlistAdvanceMode.countdown(measures: 2)) == .countdown(measures: 2))
}

@Test func songRoundTrip() throws {
    let song = Song(
        title: "Wonderwall",
        bpm: BPM(87),
        timeSignature: .fourFour,
        subdivision: .eighth,
        accentPattern: AccentPattern.standard(for: .fourFour),
        soundPreset: "acoustic",
        notes: "Capo 2",
        duration: .measures(64)
    )!
    let decoded = try roundTrip(song)
    #expect(decoded.id == song.id)
    #expect(decoded.title == song.title)
    #expect(decoded.bpm == song.bpm)
    #expect(decoded.timeSignature == song.timeSignature)
    #expect(decoded.subdivision == song.subdivision)
    #expect(decoded.accentPattern == song.accentPattern)
    #expect(decoded.soundPreset == song.soundPreset)
    #expect(decoded.notes == song.notes)
    #expect(decoded.duration == song.duration)
}

@Test func setlistRoundTrip() throws {
    let setlist = Setlist(
        name: "Tonight",
        songs: [
            Song(title: "Opener", bpm: BPM(110))!,
            Song(title: "Closer", bpm: BPM(140))!,
        ],
        advanceMode: .countdown(measures: 1)
    )
    let decoded = try roundTrip(setlist)
    #expect(decoded == setlist)
}

@Test func engineSettingsRoundTrip() throws {
    let s = EngineSettings(
        masterVolume: 0.7,
        latencyOffsetSeconds: -0.020,
        mixWithOthers: false,
        countIn: .twoMeasures,
        bpmPrecisionMode: true,
        autoResumeAfterInterruption: true,
        clickSound: .cowbell,
        midiClockEnabled: true
    )
    #expect(try roundTrip(s) == s)
}

@Test func engineSettingsDefaultsMidiOff() {
    #expect(EngineSettings().midiClockEnabled == false)
}

@Test func clickSoundRoundTrip() throws {
    for sound in ClickSound.allCases {
        #expect(try roundTrip(sound) == sound)
    }
}

@Test func clickSoundUsesStringRawValue() throws {
    let data = try JSONEncoder().encode(ClickSound.woodBlock)
    let str = String(data: data, encoding: .utf8)
    #expect(str == "\"woodBlock\"")
}

@Test func engineSettingsDefaultsToDigitalBeep() {
    let s = EngineSettings()
    #expect(s.clickSound == .digitalBeep)
}
