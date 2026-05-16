import Foundation

/// Per-beat pitch override, ±1 octave, per spec §3.1.
public enum PitchShift: Int, Hashable, Sendable, CaseIterable {
    case octaveDown = -1
    case unison     =  0
    case octaveUp   =  1

    /// Semitone offset (12 per octave).
    public var semitones: Int {
        rawValue * 12
    }
}
