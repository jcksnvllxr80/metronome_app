import Foundation

/// One scheduled audio event from the engine.
///
/// The engine pre-computes a sequence of these so the audio scheduler can
/// keep 4–8 beats queued ahead of `clock.now` per spec §1.2.
///
/// `soundOverride` / `pitchShift` come from the active `AccentPattern`'s
/// `BeatConfig` for the parent beat. Subdivision clicks (sub > 0) do NOT
/// inherit these — they always use the engine's default click sound at
/// unison pitch. Per-subdivision sound config (spec §2.3) is a separate
/// feature that's not modeled yet.
public struct Click: Hashable, Sendable {
    /// 0-based beat-in-measure. Wraps at `timeSignature.numerator`.
    public let beatIndex: Int
    /// 0-based subdivision-within-beat. `0` is the main beat; `1...(partsPerBeat-1)` are interstitial clicks.
    public let subdivisionIndex: Int
    /// 0-based measure counter since the engine started.
    public let measureIndex: Int
    /// When this click fires, in `EngineClock` time.
    public let time: TimeInterval
    /// How this click should be played.
    public let accent: AccentLevel
    /// Sound asset name to use instead of the default, when set by the
    /// active `AccentPattern`. Always `nil` for subdivisions.
    public let soundOverride: String?
    /// Per-beat pitch shift from the active `AccentPattern`. Always `.unison`
    /// for subdivisions.
    public let pitchShift: PitchShift

    public init(
        beatIndex: Int,
        subdivisionIndex: Int,
        measureIndex: Int,
        time: TimeInterval,
        accent: AccentLevel,
        soundOverride: String? = nil,
        pitchShift: PitchShift = .unison
    ) {
        self.beatIndex = beatIndex
        self.subdivisionIndex = subdivisionIndex
        self.measureIndex = measureIndex
        self.time = time
        self.accent = accent
        self.soundOverride = soundOverride
        self.pitchShift = pitchShift
    }

    /// First click of the first beat of a measure.
    public var isDownbeat: Bool {
        beatIndex == 0 && subdivisionIndex == 0
    }

    /// First click of any beat (not a subdivision).
    public var isMainBeat: Bool {
        subdivisionIndex == 0
    }
}
