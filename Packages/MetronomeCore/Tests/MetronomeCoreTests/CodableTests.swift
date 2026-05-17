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
        midiClockEnabled: true,
        midiClockReceiveEnabled: true,
        voiceCountMode: .beats
    )
    #expect(try roundTrip(s) == s)
}

@Test func engineSettingsRoundTripWithAllNewFields() throws {
    // Exercises every field added after v0.5.0: random mute, haptic
    // mode + per-accent intensities, keep-screen-awake, start-on-launch,
    // daily practice goal.
    let s = EngineSettings(
        masterVolume: 0.5,
        latencyOffsetSeconds: 0.030,
        mixWithOthers: true,
        countIn: .oneMeasure,
        bpmPrecisionMode: true,
        autoResumeAfterInterruption: false,
        clickSound: .digitalBeep,
        midiClockEnabled: false,
        midiClockReceiveEnabled: false,
        voiceCountMode: .off,
        randomMutePercentage: 25,
        hapticMode: .accentsOnly,
        hapticIntensity: HapticIntensity(soft: 0.4, normal: 0.7, loud: 0.9, accent: 1.0),
        keepScreenAwakeDuringPlayback: false,
        startOnLaunch: true,
        dailyPracticeGoalMinutes: 45
    )
    let back = try roundTrip(s)
    #expect(back.randomMutePercentage == 25)
    #expect(back.hapticMode == .accentsOnly)
    #expect(back.hapticIntensity.soft == 0.4)
    #expect(back.hapticIntensity.accent == 1.0)
    #expect(back.keepScreenAwakeDuringPlayback == false)
    #expect(back.startOnLaunch == true)
    #expect(back.dailyPracticeGoalMinutes == 45)
    #expect(back == s)
}

@Test func engineSettingsLegacyJSONDecodesWithDefaults() throws {
    // Pre-v0.8.0 payload — no haptic / random mute / new playback
    // fields. The custom decoder should fall back to defaults for
    // every missing key. `countIn` is Int-rawValue (0 == .off).
    let legacyJSON = """
    {
      "masterVolume": 0.8,
      "latencyOffsetSeconds": 0.0,
      "mixWithOthers": true,
      "countIn": 0,
      "bpmPrecisionMode": false,
      "autoResumeAfterInterruption": false,
      "clickSound": "digitalBeep",
      "midiClockEnabled": false,
      "midiClockReceiveEnabled": false,
      "voiceCountMode": "off"
    }
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(EngineSettings.self, from: legacyJSON)
    #expect(decoded.masterVolume == 0.8)
    #expect(decoded.randomMutePercentage == 0)
    #expect(decoded.hapticMode == .off)
    #expect(decoded.keepScreenAwakeDuringPlayback == true)
    #expect(decoded.startOnLaunch == false)
    #expect(decoded.dailyPracticeGoalMinutes == 0)
}

@Test func engineSettingsDefaultsMidiOff() {
    #expect(EngineSettings().midiClockEnabled == false)
    #expect(EngineSettings().midiClockReceiveEnabled == false)
}

@Test func engineSettingsDefaultsMidiSourceNameNil() {
    // Default: nil = "all sources" (legacy receiver behavior).
    #expect(EngineSettings().midiReceiveSourceName == nil)
}

@Test func engineSettingsRoundTripPreservesMidiSourceName() throws {
    let s = EngineSettings(
        midiClockReceiveEnabled: true,
        midiReceiveSourceName: "Network Session 1"
    )
    let back = try roundTrip(s)
    #expect(back.midiReceiveSourceName == "Network Session 1")
    #expect(back == s)
}

@Test func engineSettingsLegacyJSONHasNilMidiSourceName() throws {
    // Pre-picker payloads omit the field — decode must fall back to nil
    // so existing users keep "listen to all sources" behavior.
    let json = """
    {
      "masterVolume": 1.0,
      "midiClockReceiveEnabled": true
    }
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(EngineSettings.self, from: json)
    #expect(decoded.midiClockReceiveEnabled == true)
    #expect(decoded.midiReceiveSourceName == nil)
}

@Test func engineSettingsDefaultsVoiceCountOff() {
    #expect(EngineSettings().voiceCountMode == .off)
}

@Test func voiceCountModeRoundTrip() throws {
    for mode in VoiceCountMode.allCases {
        #expect(try roundTrip(mode) == mode)
    }
}

@Test func voiceCountModeImplementedFlag() {
    #expect(VoiceCountMode.off.isImplemented)
    #expect(VoiceCountMode.beats.isImplemented)
    #expect(VoiceCountMode.subdivisions.isImplemented == false)
    #expect(VoiceCountMode.measures.isImplemented == false)
    #expect(VoiceCountMode.silentCount.isImplemented == false)
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
