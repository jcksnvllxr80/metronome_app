import Foundation

/// Available click timbres, per spec §4.1's "Built-in click sounds" list.
///
/// Phase 1: 4 synthesized timbres covering distinct sonic regions —
/// percussive/tonal (wood block, cowbell), electronic (digital beep), and
/// noise-based (hi-hat). Future commits can swap individual cases for
/// bundled percussion samples without changing the public API or
/// persisted values (the `String` rawValue is the stable storage key).
public enum ClickSound: String, Hashable, Sendable, Codable, CaseIterable {
    /// Classic mechanical metronome — sharp tonal attack, fast decay.
    case woodBlock   = "woodBlock"
    /// Pure sine-wave tone burst — clean electronic click.
    case digitalBeep = "digitalBeep"
    /// Two-partial resonance with brief attack noise; mid-range sustain.
    case cowbell     = "cowbell"
    /// Broadband noise burst with high-frequency partials; very fast decay.
    case hiHat       = "hiHat"

    /// User-facing label for pickers and previews.
    public var displayName: String {
        switch self {
        case .woodBlock:   "Wood Block"
        case .digitalBeep: "Digital Beep"
        case .cowbell:     "Cowbell"
        case .hiHat:       "Hi-Hat"
        }
    }
}
