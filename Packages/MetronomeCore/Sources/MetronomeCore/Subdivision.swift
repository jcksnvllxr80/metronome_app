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

    /// Display label for the level (used in pickers + Stage indicator).
    public var displayName: String {
        switch self {
        case .none:       "Quarters"
        case .eighth:     "Eighths"
        case .triplet:    "Triplets"
        case .sixteenth:  "Sixteenths"
        case .quintuplet: "Quintuplets"
        case .sextuplet:  "Sextuplets"
        case .septuplet:  "Septuplets"
        case .octuplet:   "Octuplets"
        case .nonuplet:   "Nonuplets"
        }
    }
}

/// Per-subdivision-level configuration (spec §2.3). Lets users dial in
/// how loud and what sound the "and-a" clicks fire at, independent of
/// the parent beat's pattern. Stored in `EngineSettings` keyed by
/// `Subdivision` so each level (.eighth / .triplet / .sixteenth / …)
/// keeps its own choice across runs.
///
/// `accent` defaults to `.soft` (the hardcoded behavior before this
/// feature landed — guarantees no behavior change on upgrade until the
/// user touches the settings). `soundOverride` is `nil` by default,
/// meaning subdivisions inherit the parent beat's sound; setting it to
/// a `ClickSound.rawValue` (or an imported-sound name when §4.2 lands)
/// makes subdivisions play that sound instead.
public struct SubdivisionConfig: Hashable, Sendable, Codable {
    public var accent: AccentLevel
    public var soundOverride: String?

    public init(accent: AccentLevel = .soft, soundOverride: String? = nil) {
        self.accent = accent
        self.soundOverride = soundOverride
    }

    /// The legacy/default config that matches behavior prior to spec
    /// §2.3 — `.soft` accent, no sound override. Use this for any
    /// subdivision level that hasn't been explicitly configured by the
    /// user, so the click sequence is identical until they opt in.
    public static let legacy = SubdivisionConfig(accent: .soft, soundOverride: nil)
}
