import Foundation

/// Number of measures to count off before the song starts, per spec §10.2.
///
/// The spec is explicit about the allowed values (off / 1 / 2 / 4) — there
/// is no 3-measure count-in. Modeled as a discrete enum, not `Int`, so the
/// settings UI surface is a fixed picker and bad values can't be persisted.
public enum CountIn: Int, Hashable, Sendable, Codable, CaseIterable {
    case off          = 0
    case oneMeasure   = 1
    case twoMeasures  = 2
    case fourMeasures = 4

    /// Number of measures the count-in occupies. `0` for `.off`.
    public var measures: Int { rawValue }

    /// Whether playback should generate count-in clicks at all.
    public var isActive: Bool { self != .off }
}
