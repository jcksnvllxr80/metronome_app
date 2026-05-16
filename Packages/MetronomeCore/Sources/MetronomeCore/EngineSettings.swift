import Foundation

/// Persistable user preferences that affect engine behavior, per spec §10.
///
/// Scoped to the *engine* side (audio + playback rules). UI-only settings —
/// theme, large display mode, keep-screen-awake, lock-screen behavior —
/// don't belong here and will land alongside the UI layer.
public struct EngineSettings: Hashable, Sendable, Codable {
    /// Latency calibration range per spec §10.1: ±50 ms.
    public static let latencyOffsetRange: ClosedRange<TimeInterval> = -0.050...0.050

    /// 0.0–1.0. Applied to every click before output mix.
    public var masterVolume: Double
    /// Offset in seconds added at audio scheduling time. Negative = fire
    /// earlier (compensating for Bluetooth headphone latency). Clamped to
    /// `latencyOffsetRange`.
    public var latencyOffsetSeconds: TimeInterval
    /// `AVAudioSession` option — when true, audio coexists with music apps
    /// and tuners (`.mixWithOthers`). Per spec §10.1.
    public var mixWithOthers: Bool
    /// Default count-in for `engine.start()`. Per-start overrides win.
    public var countIn: CountIn
    /// When true, the BPM UI surfaces the 0.1 BPM tenths. Per spec §10.3.
    /// Engine doesn't read this — it's a display setting kept here because
    /// it lives next to BPM-related preferences and persists the same way.
    public var bpmPrecisionMode: Bool
    /// When `true`, the engine resumes automatically after an audio session
    /// interruption ends (the system also has to set `.shouldResume` in
    /// the interruption-ended notification). Default `false` per Apple HIG:
    /// users expect a phone call → metronome stays paused → they press
    /// Play again. Spec §16 calls this out as an explicit user setting.
    public var autoResumeAfterInterruption: Bool
    /// Which built-in click timbre to play. The audio scheduler reads this
    /// every refill pass (~50 ms) so changes in the Settings sheet are
    /// audible almost immediately. Per-song `soundPreset` overrides this
    /// when set (future commit).
    public var clickSound: ClickSound

    public init(
        masterVolume: Double = 1.0,
        latencyOffsetSeconds: TimeInterval = 0.0,
        mixWithOthers: Bool = true,
        countIn: CountIn = .off,
        bpmPrecisionMode: Bool = false,
        autoResumeAfterInterruption: Bool = false,
        clickSound: ClickSound = .digitalBeep
    ) {
        self.masterVolume = max(0.0, min(1.0, masterVolume))
        self.latencyOffsetSeconds = max(
            Self.latencyOffsetRange.lowerBound,
            min(Self.latencyOffsetRange.upperBound, latencyOffsetSeconds)
        )
        self.mixWithOthers = mixWithOthers
        self.countIn = countIn
        self.bpmPrecisionMode = bpmPrecisionMode
        self.autoResumeAfterInterruption = autoResumeAfterInterruption
        self.clickSound = clickSound
    }
}
