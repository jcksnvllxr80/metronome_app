import Foundation

/// Configuration for a single beat within an `AccentPattern`, per spec §3.1.
///
/// `soundOverride` references a sound asset by name (built-in or user-imported).
/// Stored as `String?` rather than a typed `Sound` reference so the engine
/// doesn't depend on the sound library yet — the resolver lives at audio
/// scheduling time. `nil` means "use the engine's default sound for this beat's
/// accent level."
public struct BeatConfig: Hashable, Sendable {
    public let accent: AccentLevel
    public let soundOverride: String?
    public let pitchShift: PitchShift

    public init(
        accent: AccentLevel = .normal,
        soundOverride: String? = nil,
        pitchShift: PitchShift = .unison
    ) {
        self.accent = accent
        self.soundOverride = soundOverride
        self.pitchShift = pitchShift
    }

    /// Convenience: the typical downbeat shape.
    public static let downbeat = BeatConfig(accent: .accent)
    /// Convenience: the typical mid-measure beat.
    public static let mainBeat = BeatConfig(accent: .normal)
    /// Convenience: a muted beat (still consumes its slot in the measure).
    public static let muted = BeatConfig(accent: .mute)
}
