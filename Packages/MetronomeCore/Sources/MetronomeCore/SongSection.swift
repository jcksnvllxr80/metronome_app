import Foundation

/// One section of a multi-section song (spec §7.3).
///
/// A sectioned song plays each section in order: intro 16 bars @ 90 →
/// verse 32 bars @ 120 → bridge 8 bars @ 100, etc. Each section
/// carries its own complete metronome state — BPM, meter, subdivision,
/// accent pattern, sound preset. Engine integration plays through
/// sections via `SongSectionPlayer` (parallel to `SetlistPlayer` for
/// setlist auto-advance).
///
/// Mirrors `Song`'s scoping invariant: `accentPattern.timeSignature`
/// must equal `timeSignature`, enforced at init and Codable decode.
/// Loop / DC al fine / repeat markers are out of scope for v1.
public struct SongSection: Hashable, Sendable, Identifiable, Codable {
    public let id: UUID
    public var name: String?
    public var bpm: BPM
    public private(set) var timeSignature: TimeSignature
    public var subdivision: Subdivision
    public var measureCount: Int
    public private(set) var accentPattern: AccentPattern?
    public var soundPreset: String?

    /// Returns `nil` if `measureCount < 1` or
    /// `accentPattern.timeSignature != timeSignature`.
    public init?(
        id: UUID = UUID(),
        name: String? = nil,
        bpm: BPM,
        timeSignature: TimeSignature = .fourFour,
        subdivision: Subdivision = .none,
        measureCount: Int,
        accentPattern: AccentPattern? = nil,
        soundPreset: String? = nil
    ) {
        guard measureCount >= 1 else { return nil }
        if let pattern = accentPattern, pattern.timeSignature != timeSignature {
            return nil
        }
        self.id = id
        self.name = name
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.subdivision = subdivision
        self.measureCount = measureCount
        self.accentPattern = accentPattern
        self.soundPreset = soundPreset
    }

    /// Set or clear the accent pattern. Returns `true` if accepted,
    /// `false` on time-signature mismatch (state unchanged on false).
    @discardableResult
    public mutating func setAccentPattern(_ pattern: AccentPattern?) -> Bool {
        if let pattern, pattern.timeSignature != timeSignature {
            return false
        }
        accentPattern = pattern
        return true
    }

    /// Change time signature, clearing the accent pattern if it no
    /// longer applies — same rule as `Song.setTimeSignature`.
    public mutating func setTimeSignature(_ newTS: TimeSignature) {
        if let pattern = accentPattern, pattern.timeSignature != newTS {
            accentPattern = nil
        }
        timeSignature = newTS
    }
}

// MARK: - Codable

extension SongSection {
    private enum CodingKeys: String, CodingKey {
        case id, name, bpm, timeSignature, subdivision, measureCount, accentPattern, soundPreset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let name = try c.decodeIfPresent(String.self, forKey: .name)
        let bpm = try c.decode(BPM.self, forKey: .bpm)
        let ts = try c.decode(TimeSignature.self, forKey: .timeSignature)
        let sub = try c.decode(Subdivision.self, forKey: .subdivision)
        let measureCount = try c.decode(Int.self, forKey: .measureCount)
        let pattern = try c.decodeIfPresent(AccentPattern.self, forKey: .accentPattern)
        let soundPreset = try c.decodeIfPresent(String.self, forKey: .soundPreset)
        guard let section = SongSection(
            id: id,
            name: name,
            bpm: bpm,
            timeSignature: ts,
            subdivision: sub,
            measureCount: measureCount,
            accentPattern: pattern,
            soundPreset: soundPreset
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .measureCount, in: c,
                debugDescription: "measureCount must be >= 1 and accentPattern must match timeSignature"
            )
        }
        self = section
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(bpm, forKey: .bpm)
        try c.encode(timeSignature, forKey: .timeSignature)
        try c.encode(subdivision, forKey: .subdivision)
        try c.encode(measureCount, forKey: .measureCount)
        try c.encodeIfPresent(accentPattern, forKey: .accentPattern)
        try c.encodeIfPresent(soundPreset, forKey: .soundPreset)
    }
}
