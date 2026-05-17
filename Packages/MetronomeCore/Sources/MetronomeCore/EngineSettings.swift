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
    /// when set.
    public var clickSound: ClickSound
    /// When `true`, the engine sends MIDI Clock (0xF8 at 24 PPQ) plus
    /// Start (0xFA) / Stop (0xFC) messages on its virtual MIDI source so
    /// DAWs and other devices can sync tempo. Spec §12.2. Default off —
    /// most users don't need MIDI sync, and an enabled virtual source is
    /// visible to other apps even when nothing's playing.
    public var midiClockEnabled: Bool
    /// When `true`, the engine listens for incoming MIDI Clock and
    /// follows external tempo — slave mode (spec §12.2). MIDI Start/Stop
    /// drives engine.start/stop; MIDI Clock drives engine.setBPM.
    /// Mutually compatible with `midiClockEnabled` (send + receive can
    /// both be on, though feedback is avoided by name-filtering our own
    /// source).
    public var midiClockReceiveEnabled: Bool
    /// Voice-count mode (spec §5). Phase 1 supports `.off` and `.beats`;
    /// other cases are reserved enum values that currently behave like
    /// `.off`. See `VoiceCountMode.isImplemented`.
    public var voiceCountMode: VoiceCountMode
    /// Random-mute mode percentage (spec §6.4 speed trainer "random mute"):
    /// 0 = off, 10–50 = active range. Stored as Int because the slider
    /// snaps to whole percentages. Clamped to `randomMuteRange` on init
    /// (values 1–9 round up to 10; 51+ round down to 50).
    public var randomMutePercentage: Int
    /// Haptic feedback mode (spec §9). Default `.off` — many users
    /// want audio without buzz. The `HapticScheduler` reads this each
    /// refill pass so toggling in Settings takes effect immediately.
    public var hapticMode: HapticMode

    /// Allowed range for `randomMutePercentage` when active (0 is special-
    /// cased as "off"). Per spec §6.4 — wider ranges than 50% don't help
    /// the training effect.
    public static let randomMuteRange: ClosedRange<Int> = 10...50

    public init(
        masterVolume: Double = 1.0,
        latencyOffsetSeconds: TimeInterval = 0.0,
        mixWithOthers: Bool = true,
        countIn: CountIn = .off,
        bpmPrecisionMode: Bool = false,
        autoResumeAfterInterruption: Bool = false,
        clickSound: ClickSound = .digitalBeep,
        midiClockEnabled: Bool = false,
        midiClockReceiveEnabled: Bool = false,
        voiceCountMode: VoiceCountMode = .off,
        randomMutePercentage: Int = 0,
        hapticMode: HapticMode = .off
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
        self.midiClockEnabled = midiClockEnabled
        self.midiClockReceiveEnabled = midiClockReceiveEnabled
        self.voiceCountMode = voiceCountMode
        // 0 stays 0 (off). Anything else clamps to the active range.
        if randomMutePercentage <= 0 {
            self.randomMutePercentage = 0
        } else {
            self.randomMutePercentage = max(
                Self.randomMuteRange.lowerBound,
                min(Self.randomMuteRange.upperBound, randomMutePercentage)
            )
        }
        self.hapticMode = hapticMode
    }
}
