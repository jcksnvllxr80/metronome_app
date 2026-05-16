import Foundation

/// A named bundle of metronome settings, per spec §7.1.
///
/// Single-section only for now (Phase 2). Multi-section songs (spec §7.3,
/// Phase 3) will either extend this type with a `sections: [Section]`
/// array or introduce a `SectionedSong` peer — the public API kept on this
/// type today should survive either path.
///
/// `accentPattern` is `private(set)` to preserve the spec §3.2 invariant
/// that a pattern is scoped to a specific time signature: clients mutate
/// via `setAccentPattern(_:)` (returns `false` on mismatch) or
/// `setTimeSignature(_:)` (auto-clears a now-mismatched pattern). The
/// init also enforces this — passing a mismatched pattern returns `nil`.
public struct Song: Hashable, Sendable, Identifiable, Codable {
    public let id: UUID
    public var title: String
    public var bpm: BPM
    public private(set) var timeSignature: TimeSignature
    public var subdivision: Subdivision
    public private(set) var accentPattern: AccentPattern?
    /// Sound asset/preset name (resolved at audio scheduling time). Same
    /// deferred-binding pattern as `BeatConfig.soundOverride`.
    public var soundPreset: String?
    public var notes: String?
    public var duration: SongDuration?

    /// Returns `nil` when `accentPattern.timeSignature != timeSignature`.
    public init?(
        id: UUID = UUID(),
        title: String,
        bpm: BPM,
        timeSignature: TimeSignature = .fourFour,
        subdivision: Subdivision = .none,
        accentPattern: AccentPattern? = nil,
        soundPreset: String? = nil,
        notes: String? = nil,
        duration: SongDuration? = nil
    ) {
        if let pattern = accentPattern, pattern.timeSignature != timeSignature {
            return nil
        }
        self.id = id
        self.title = title
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.subdivision = subdivision
        self.accentPattern = accentPattern
        self.soundPreset = soundPreset
        self.notes = notes
        self.duration = duration
    }

    /// Set or clear the accent pattern. Returns `true` if accepted, `false`
    /// on time-signature mismatch (state is unchanged in that case).
    @discardableResult
    public mutating func setAccentPattern(_ pattern: AccentPattern?) -> Bool {
        if let pattern, pattern.timeSignature != timeSignature {
            return false
        }
        accentPattern = pattern
        return true
    }

    /// Change time signature, clearing the accent pattern if it no longer
    /// applies. Patterns don't translate across meters (spec §3.2).
    public mutating func setTimeSignature(_ newTS: TimeSignature) {
        if let pattern = accentPattern, pattern.timeSignature != newTS {
            accentPattern = nil
        }
        timeSignature = newTS
    }
}

// MARK: - Codable

extension Song {
    private enum CodingKeys: String, CodingKey {
        case id, title, bpm, timeSignature, subdivision, accentPattern
        case soundPreset, notes, duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let bpm = try container.decode(BPM.self, forKey: .bpm)
        let ts = try container.decode(TimeSignature.self, forKey: .timeSignature)
        let sub = try container.decode(Subdivision.self, forKey: .subdivision)
        let pattern = try container.decodeIfPresent(AccentPattern.self, forKey: .accentPattern)
        let soundPreset = try container.decodeIfPresent(String.self, forKey: .soundPreset)
        let notes = try container.decodeIfPresent(String.self, forKey: .notes)
        let duration = try container.decodeIfPresent(SongDuration.self, forKey: .duration)
        guard let song = Song(
            id: id,
            title: title,
            bpm: bpm,
            timeSignature: ts,
            subdivision: sub,
            accentPattern: pattern,
            soundPreset: soundPreset,
            notes: notes,
            duration: duration
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .accentPattern,
                in: container,
                debugDescription: "Accent pattern's time signature doesn't match the song's"
            )
        }
        self = song
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(bpm, forKey: .bpm)
        try container.encode(timeSignature, forKey: .timeSignature)
        try container.encode(subdivision, forKey: .subdivision)
        try container.encodeIfPresent(accentPattern, forKey: .accentPattern)
        try container.encodeIfPresent(soundPreset, forKey: .soundPreset)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

// MARK: - Engine integration

extension MetronomeEngine {
    /// Load `song`'s settings into the engine (BPM, time signature, subdivision,
    /// accent pattern). Re-anchors the click sequence if running. Does NOT
    /// auto-start — call `start()` separately. `song.duration` is the caller's
    /// concern (the auto-stop scheduler isn't on the engine yet).
    public func apply(_ song: Song) {
        // The song's invariant guarantees pattern matches its own time sig,
        // so we can set TS first then pattern without an intermediate clear.
        setTimeSignature(song.timeSignature)
        setBPM(song.bpm)
        setSubdivision(song.subdivision)
        _ = setAccentPattern(song.accentPattern)
    }
}
