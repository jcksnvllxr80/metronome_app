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
    /// True for clicks that fall within the engine's count-in window. The
    /// accent pattern is NOT applied to these clicks; the UI may render them
    /// differently (e.g. dimmed) and the audio layer may choose a quieter
    /// sample.
    public let isCountIn: Bool

    public init(
        beatIndex: Int,
        subdivisionIndex: Int,
        measureIndex: Int,
        time: TimeInterval,
        accent: AccentLevel,
        soundOverride: String? = nil,
        pitchShift: PitchShift = .unison,
        isCountIn: Bool = false
    ) {
        self.beatIndex = beatIndex
        self.subdivisionIndex = subdivisionIndex
        self.measureIndex = measureIndex
        self.time = time
        self.accent = accent
        self.soundOverride = soundOverride
        self.pitchShift = pitchShift
        self.isCountIn = isCountIn
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

/// One scheduled polyrhythm event (spec §2.4). Parallel to `Click` but
/// without beat / subdivision / accent semantics — polyrhythm clicks are
/// a flat stream of N evenly-spaced pulses per primary-meter measure,
/// each carrying just the sound + volume from the active
/// `PolyrhythmConfig`. They share the primary measure's start boundary
/// so polyrhythm[0] of each measure aligns with the downbeat.
public struct PolyClick: Hashable, Sendable {
    /// 0-based primary-meter measure this pulse belongs to. Matches
    /// `Click.measureIndex` for the same measure.
    public let measureIndex: Int
    /// 0-based pulse-within-measure, 0…(pulses-1).
    public let pulseIndex: Int
    /// When this pulse fires, in `EngineClock` time.
    public let time: TimeInterval
    /// Sound to play, from the active `PolyrhythmConfig`.
    public let sound: ClickSound
    /// 0.0–1.0 stream volume from the active `PolyrhythmConfig`. The
    /// audio scheduler still multiplies by `EngineSettings.masterVolume`
    /// at output time.
    public let volume: Double

    public init(
        measureIndex: Int,
        pulseIndex: Int,
        time: TimeInterval,
        sound: ClickSound,
        volume: Double
    ) {
        self.measureIndex = measureIndex
        self.pulseIndex = pulseIndex
        self.time = time
        self.sound = sound
        self.volume = volume
    }
}
