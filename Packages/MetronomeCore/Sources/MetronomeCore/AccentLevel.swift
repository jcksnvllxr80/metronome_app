import Foundation

/// Per-beat accent level per spec §3.1. Five discrete values; not a continuous
/// volume. Per beat the engine also stores an optional sound override and a
/// ±1 octave pitch override — those are separate concerns from accent level.
public enum AccentLevel: Int, Hashable, Sendable, Codable, CaseIterable {
    case mute   = 0
    case soft   = 1
    case normal = 2
    case loud   = 3
    case accent = 4
}
