import Foundation

/// Voice-count playback mode, per spec §5.
///
/// Phase 1 implements `.off` and `.beats` — main beats get a per-beat
/// pitched tone (descending from C5, distinct per beat number) so users
/// hear "which beat" without needing the click pattern alone. The other
/// cases are reserved in the enum for future commits:
/// - `.subdivisions` — "one-and-two-and" / "one-e-and-a"
/// - `.measures` — announce measure number at downbeat
/// - `.silentCount` — only count first N beats of each measure
///
/// Real pre-recorded voice samples (per spec) would replace the
/// synthesized tones without changing the public API or settings key
/// (the `String` rawValue is the stable persistence key).
public enum VoiceCountMode: String, Hashable, Sendable, Codable, CaseIterable {
    case off
    case beats
    case subdivisions
    case measures
    case silentCount

    /// User-facing label.
    public var displayName: String {
        switch self {
        case .off:          "Off"
        case .beats:        "Count Beats"
        case .subdivisions: "Count Subdivisions"
        case .measures:     "Count Measures"
        case .silentCount:  "Silent Count Training"
        }
    }

    /// Whether this mode replaces or augments normal clicks during playback.
    /// Phase 1: only `.beats` is implemented and audible.
    public var isImplemented: Bool {
        self == .off || self == .beats
    }
}
