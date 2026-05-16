import Foundation

/// Beats per minute. Range 20.0–400.0 in 0.1 increments per spec §1.1.
/// Stored as `Double` (not `Int`) so the "precision mode" setting can expose
/// the tenths without lossy conversion.
public struct BPM: Hashable, Sendable, Comparable, Codable {
    public static let minimum: Double = 20.0
    public static let maximum: Double = 400.0
    public static let precision: Double = 0.1

    public let value: Double

    /// Clamps to [20, 400] and snaps to 0.1 increments.
    public init(_ raw: Double) {
        let clamped = max(Self.minimum, min(Self.maximum, raw))
        self.value = (clamped * 10).rounded() / 10
    }

    /// Whole-BPM rounding for the default UI display.
    public var displayInt: Int {
        Int(value.rounded())
    }

    /// Seconds between beats at this tempo.
    public var beatPeriod: TimeInterval {
        60.0 / value
    }

    public static func < (lhs: BPM, rhs: BPM) -> Bool {
        lhs.value < rhs.value
    }

    // Codable — route through the clamping/snapping init so persisted
    // values that are out-of-spec (corrupted or written by an old build)
    // get normalized on read.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Double.self)
        self = BPM(raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
