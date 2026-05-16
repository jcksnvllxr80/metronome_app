import Foundation

/// Subdivisions per beat, per spec §2.3.
/// `.none` is quarter notes only (1 part per beat). Custom 8/9 are modeled
/// explicitly rather than as `case custom(Int)` so the type stays `Hashable`
/// without manual conformance and the UI can render a fixed picker.
///
/// `String` rawValue gives us free `Codable` for persistence (the raw key
/// is the source of truth, not the case ordinal — adding a case later
/// won't shift existing values).
public enum Subdivision: String, Hashable, Sendable, Codable, CaseIterable {
    case none = "none"
    case eighth = "eighth"
    case triplet = "triplet"
    case sixteenth = "sixteenth"
    case quintuplet = "quintuplet"
    case sextuplet = "sextuplet"
    case septuplet = "septuplet"
    case octuplet = "octuplet"
    case nonuplet = "nonuplet"

    /// Number of clicks per main beat at this subdivision level.
    public var partsPerBeat: Int {
        switch self {
        case .none:       1
        case .eighth:     2
        case .triplet:    3
        case .sixteenth:  4
        case .quintuplet: 5
        case .sextuplet:  6
        case .septuplet:  7
        case .octuplet:   8
        case .nonuplet:   9
        }
    }
}
