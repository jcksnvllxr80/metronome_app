import Testing
import Foundation
@testable import MetronomeCore

// MARK: - Construction

@Test func sectionRejectsZeroMeasureCount() {
    #expect(SongSection(bpm: BPM(120), measureCount: 0) == nil)
    #expect(SongSection(bpm: BPM(120), measureCount: -1) == nil)
}

@Test func sectionAcceptsMinimalConstruction() {
    let s = SongSection(bpm: BPM(120), measureCount: 4)
    #expect(s != nil)
    #expect(s?.timeSignature == .fourFour)
    #expect(s?.subdivision == Subdivision.none)
    #expect(s?.accentPattern == nil)
}

@Test func sectionRejectsPatternMismatch() {
    // A pattern in 4/4 can't be attached to a section in 7/8.
    let pattern = AccentPattern.standard(for: .fourFour)
    let sevenEight = TimeSignature(numerator: 7, denominator: .eighth)!
    let s = SongSection(
        bpm: BPM(120),
        timeSignature: sevenEight,
        measureCount: 4,
        accentPattern: pattern
    )
    #expect(s == nil)
}

@Test func sectionSetTimeSignatureClearsOrphanPattern() {
    let pattern = AccentPattern.standard(for: .fourFour)
    var s = SongSection(
        bpm: BPM(120),
        timeSignature: .fourFour,
        measureCount: 8,
        accentPattern: pattern
    )!
    let sevenEight = TimeSignature(numerator: 7, denominator: .eighth)!
    s.setTimeSignature(sevenEight)
    #expect(s.accentPattern == nil)
    #expect(s.timeSignature == sevenEight)
}

// MARK: - Codable

@Test func sectionCodableRoundTrip() throws {
    let s = SongSection(
        name: "Verse",
        bpm: BPM(120),
        timeSignature: .fourFour,
        subdivision: .eighth,
        measureCount: 32,
        accentPattern: AccentPattern.standard(for: .fourFour),
        soundPreset: "cowbell"
    )!
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(SongSection.self, from: data)
    #expect(back == s)
}

@Test func sectionCodableRejectsCorruptMeasureCount() {
    let json = """
    {
      "id": "\(UUID().uuidString)",
      "bpm": 120,
      "timeSignature": {"numerator": 4, "denominator": 4},
      "subdivision": "none",
      "measureCount": 0
    }
    """.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(SongSection.self, from: json)
    }
}

// MARK: - Song.sections integration

@Test func songIsMultiSectionWhenSectionsArePopulated() {
    let plain = Song(title: "Plain", bpm: BPM(120))!
    #expect(plain.isMultiSection == false)

    let s1 = SongSection(name: "Intro", bpm: BPM(90), measureCount: 16)!
    let s2 = SongSection(name: "Verse", bpm: BPM(120), measureCount: 32)!
    let sectioned = Song(
        title: "Sectioned",
        bpm: BPM(120),
        sections: [s1, s2]
    )!
    #expect(sectioned.isMultiSection == true)
    #expect(sectioned.sections?.count == 2)
}

@Test func songNormalizesEmptySectionsToNil() {
    // Empty array is semantically the same as no sections — Song
    // normalizes to nil so isMultiSection has a clean check.
    let song = Song(title: "Test", bpm: BPM(120), sections: [])!
    #expect(song.sections == nil)
    #expect(song.isMultiSection == false)
}

@Test func songWithSectionsCodableRoundTrip() throws {
    let s1 = SongSection(name: "Intro", bpm: BPM(90), measureCount: 16)!
    let s2 = SongSection(
        name: "Bridge",
        bpm: BPM(100),
        timeSignature: TimeSignature(numerator: 6, denominator: .eighth)!,
        subdivision: .triplet,
        measureCount: 8
    )!
    let song = Song(title: "Wonderwall", bpm: BPM(87), sections: [s1, s2])!
    let data = try JSONEncoder().encode(song)
    let back = try JSONDecoder().decode(Song.self, from: data)
    #expect(back == song)
    #expect(back.sections?.count == 2)
    #expect(back.sections?[1].name == "Bridge")
}

@Test func legacySongJSONWithoutSectionsDecodesAsNil() throws {
    // Pre-§7.3 payload doesn't include a `sections` key. Decoder
    // should treat the absence as nil and song.isMultiSection == false.
    let json = """
    {
      "id": "\(UUID().uuidString)",
      "title": "Legacy Song",
      "bpm": 100,
      "timeSignature": {"numerator": 4, "denominator": 4},
      "subdivision": "none"
    }
    """.data(using: .utf8)!
    let song = try JSONDecoder().decode(Song.self, from: json)
    #expect(song.sections == nil)
    #expect(song.isMultiSection == false)
}
