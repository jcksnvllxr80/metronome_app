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
    /// How many times the section's `measureCount` measures play
    /// before the player advances to the next section. Default 1
    /// (single pass). Minimum 1 — values < 1 are clamped at init.
    /// Spec §7.3 "Optional repeat markers" — the simplest form.
    public var repeatCount: Int
    /// What happens after the section's repeats complete. Default
    /// `.continue` advances to the next section. `.stop` ends the
    /// song here. `.daCapoAlFine` jumps back to section 0 and plays
    /// in al-fine mode (see `isFine`). Spec §7.3.
    public var endAction: SectionEndAction
    /// When true, this section is the "Fine" point in a D.C. al Fine
    /// or D.S. al Fine structure: if the player is in al-fine mode
    /// (because some earlier section had `endAction = .daCapoAlFine`
    /// or `.dalSegnoAlFine`), playback stops after this section's
    /// repeats finish. Has no effect when not in al-fine mode.
    /// Spec §7.3.
    public var isFine: Bool
    /// When true, this section is the "Segno" mark — the jump target
    /// for any later section with `endAction = .dalSegnoAlFine` or
    /// `.dalSegnoAlCoda`. Like the head section in D.C. notation but
    /// explicit so the form's real repeat target can sit mid-song.
    /// When multiple sections carry the flag, D.S. jumps to the
    /// nearest preceding one. Spec §7.3.
    public var isSegno: Bool
    /// When true, this section is the "Coda" target — the forward
    /// jump destination during the second pass of a `.daCapoAlCoda`
    /// or `.dalSegnoAlCoda` form. Player scans forward from the
    /// trigger section for the nearest `isCoda` mark on the al-coda
    /// pass. Multiple coda marks are allowed but only the first
    /// after the trigger is targeted. Spec §7.3.
    public var isCoda: Bool

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
        soundPreset: String? = nil,
        repeatCount: Int = 1,
        endAction: SectionEndAction = .continue,
        isFine: Bool = false,
        isSegno: Bool = false,
        isCoda: Bool = false
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
        self.repeatCount = max(1, repeatCount)
        self.endAction = endAction
        self.isFine = isFine
        self.isSegno = isSegno
        self.isCoda = isCoda
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
        case id, name, bpm, timeSignature, subdivision, measureCount,
             accentPattern, soundPreset, repeatCount, endAction, isFine,
             isSegno, isCoda
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
        // Defaults for legacy rows that pre-date each field.
        let repeatCount = (try c.decodeIfPresent(Int.self, forKey: .repeatCount)) ?? 1
        let endAction = (try c.decodeIfPresent(SectionEndAction.self, forKey: .endAction)) ?? .continue
        let isFine = (try c.decodeIfPresent(Bool.self, forKey: .isFine)) ?? false
        let isSegno = (try c.decodeIfPresent(Bool.self, forKey: .isSegno)) ?? false
        let isCoda = (try c.decodeIfPresent(Bool.self, forKey: .isCoda)) ?? false
        guard let section = SongSection(
            id: id,
            name: name,
            bpm: bpm,
            timeSignature: ts,
            subdivision: sub,
            measureCount: measureCount,
            accentPattern: pattern,
            soundPreset: soundPreset,
            repeatCount: repeatCount,
            endAction: endAction,
            isFine: isFine,
            isSegno: isSegno,
            isCoda: isCoda
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
        // Always encode — Codable consumers (CSV export, hand-crafted
        // JSON, tests) shouldn't have to guess at defaults.
        try c.encode(repeatCount, forKey: .repeatCount)
        try c.encode(endAction, forKey: .endAction)
        try c.encode(isFine, forKey: .isFine)
        try c.encode(isSegno, forKey: .isSegno)
        try c.encode(isCoda, forKey: .isCoda)
    }
}
