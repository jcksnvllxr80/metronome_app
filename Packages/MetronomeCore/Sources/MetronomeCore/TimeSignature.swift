import Foundation

/// Time signature. Numerator 1–32, denominator ∈ {1, 2, 4, 8, 16, 32} per spec §2.1.
/// Custom/odd meters must be fully supported — `init?` rejects out-of-range numerators
/// but does not constrain to "musical" presets.
public struct TimeSignature: Hashable, Sendable, Codable {
    public enum Denominator: Int, Hashable, Sendable, Codable, CaseIterable {
        case whole = 1
        case half = 2
        case quarter = 4
        case eighth = 8
        case sixteenth = 16
        case thirtySecond = 32
    }

    public static let minNumerator = 1
    public static let maxNumerator = 32

    public let numerator: Int
    public let denominator: Denominator

    /// Returns `nil` if `numerator` is outside [1, 32].
    public init?(numerator: Int, denominator: Denominator) {
        guard (Self.minNumerator...Self.maxNumerator).contains(numerator) else {
            return nil
        }
        self.numerator = numerator
        self.denominator = denominator
    }

    public static let fourFour    = TimeSignature(numerator: 4, denominator: .quarter)!
    public static let threeFour   = TimeSignature(numerator: 3, denominator: .quarter)!
    public static let twoFour     = TimeSignature(numerator: 2, denominator: .quarter)!
    public static let fiveFour    = TimeSignature(numerator: 5, denominator: .quarter)!
    public static let sixEight    = TimeSignature(numerator: 6, denominator: .eighth)!
    public static let sevenEight  = TimeSignature(numerator: 7, denominator: .eighth)!
    public static let nineEight   = TimeSignature(numerator: 9, denominator: .eighth)!
    public static let twelveEight = TimeSignature(numerator: 12, denominator: .eighth)!

    // Codable — preserves the range invariant by routing through init?.
    // Corrupt/out-of-range persisted data fails decoding loudly rather
    // than silently round-tripping invalid state.
    private enum CodingKeys: String, CodingKey {
        case numerator, denominator
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let num = try container.decode(Int.self, forKey: .numerator)
        let den = try container.decode(Denominator.self, forKey: .denominator)
        guard let ts = TimeSignature(numerator: num, denominator: den) else {
            throw DecodingError.dataCorruptedError(
                forKey: .numerator,
                in: container,
                debugDescription: "Invalid numerator \(num) (must be 1–32)"
            )
        }
        self = ts
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(numerator, forKey: .numerator)
        try container.encode(denominator, forKey: .denominator)
    }
}
