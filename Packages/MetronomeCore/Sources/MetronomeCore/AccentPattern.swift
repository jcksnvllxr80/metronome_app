import Foundation

/// A named per-beat accent pattern scoped to a specific `TimeSignature`,
/// per spec §3.2 + CLAUDE.md.
///
/// **Scoping invariant:** a pattern is meaningless without its time signature
/// — a 7/8 pattern with 2+2+3 grouping has no sensible mapping onto 4/4. This
/// type encodes that by storing the `timeSignature` and validating the `beats`
/// array length at construction. `MetronomeEngine` clears a pattern when the
/// engine's time signature changes to one that doesn't match.
public struct AccentPattern: Hashable, Sendable, Codable {
    public let name: String
    public let timeSignature: TimeSignature
    public let beats: [BeatConfig]

    /// Returns `nil` if `beats.count != timeSignature.numerator`.
    public init?(name: String, timeSignature: TimeSignature, beats: [BeatConfig]) {
        guard beats.count == timeSignature.numerator else { return nil }
        self.name = name
        self.timeSignature = timeSignature
        self.beats = beats
    }

    /// Config for the given 0-based beat index. Wraps modulo `beats.count` so
    /// callers don't need to know the measure boundary.
    public func config(forBeat beatIndex: Int) -> BeatConfig {
        beats[beatIndex % beats.count]
    }

    /// "Standard accent" — downbeat is `.accent`, everything else `.normal`.
    /// This is the spec §3.2 default that "quick toggle" flips to.
    public static func standard(
        for timeSignature: TimeSignature,
        name: String = "Standard"
    ) -> AccentPattern {
        var beats = Array(repeating: BeatConfig.mainBeat, count: timeSignature.numerator)
        beats[0] = .downbeat
        return AccentPattern(name: name, timeSignature: timeSignature, beats: beats)!
    }

    // Codable — routes through init? so a persisted pattern whose
    // beats.count drifts from its timeSignature.numerator fails decoding
    // loudly. Preserves the spec §3.2 invariant on read.
    private enum CodingKeys: String, CodingKey {
        case name, timeSignature, beats
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let ts = try container.decode(TimeSignature.self, forKey: .timeSignature)
        let beats = try container.decode([BeatConfig].self, forKey: .beats)
        guard let pattern = AccentPattern(name: name, timeSignature: ts, beats: beats) else {
            throw DecodingError.dataCorruptedError(
                forKey: .beats,
                in: container,
                debugDescription: "Beats count \(beats.count) doesn't match time signature \(ts.numerator)"
            )
        }
        self = pattern
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(timeSignature, forKey: .timeSignature)
        try container.encode(beats, forKey: .beats)
    }
}
