import Foundation

/// Per-accent haptic intensity (spec §9). Each slider is 0…1, mapped
/// onto `CHHapticEventParameter` intensity. Mute is always 0 and isn't
/// configurable (a muted beat has no haptic event to attach intensity
/// to). Defaults match `HapticScheduler`'s pre-config curve: soft and
/// normal are subtle; loud is firm; accent is the strongest.
public struct HapticIntensity: Hashable, Sendable, Codable {
    public var soft: Double
    public var normal: Double
    public var loud: Double
    public var accent: Double

    public init(soft: Double = 0.3, normal: Double = 0.6, loud: Double = 0.85, accent: Double = 1.0) {
        self.soft = Self.clamp(soft)
        self.normal = Self.clamp(normal)
        self.loud = Self.clamp(loud)
        self.accent = Self.clamp(accent)
    }

    private static func clamp(_ v: Double) -> Double { max(0, min(1, v)) }

    /// Intensity to apply for a given accent level. Mute returns 0 —
    /// the scheduler should already filter mute clicks before this is
    /// queried, but this defends against accidental misuse.
    public func value(for accent: AccentLevel) -> Double {
        switch accent {
        case .mute:   return 0
        case .soft:   return soft
        case .normal: return normal
        case .loud:   return loud
        case .accent: return self.accent
        }
    }
}

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
    /// Per-accent haptic intensity (spec §9). 4 sliders (mute is fixed
    /// at 0). HapticScheduler reads these instead of the hardcoded
    /// curve it used at v0.8.0.
    public var hapticIntensity: HapticIntensity
    /// When `true`, the screen stays on while the engine is playing
    /// (spec §10.2). Defaults `true` because most users put the phone
    /// on a music stand and don't want it sleeping mid-song. The view
    /// layer toggles `UIApplication.isIdleTimerDisabled` per this flag.
    public var keepScreenAwakeDuringPlayback: Bool

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
        hapticMode: HapticMode = .off,
        hapticIntensity: HapticIntensity = HapticIntensity(),
        keepScreenAwakeDuringPlayback: Bool = true
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
        self.hapticIntensity = hapticIntensity
        self.keepScreenAwakeDuringPlayback = keepScreenAwakeDuringPlayback
    }
}

extension EngineSettings {
    /// Custom Codable to provide a default for `hapticIntensity` when
    /// decoding pre-v0.8.2 payloads that don't carry the field. SwiftData
    /// handles this via its nullable-column migration, but JSON Codable
    /// (used by tests, exports, and any debug fixtures) needs the
    /// explicit fallback.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            masterVolume: try c.decodeIfPresent(Double.self, forKey: .masterVolume) ?? 1.0,
            latencyOffsetSeconds: try c.decodeIfPresent(TimeInterval.self, forKey: .latencyOffsetSeconds) ?? 0,
            mixWithOthers: try c.decodeIfPresent(Bool.self, forKey: .mixWithOthers) ?? true,
            countIn: try c.decodeIfPresent(CountIn.self, forKey: .countIn) ?? .off,
            bpmPrecisionMode: try c.decodeIfPresent(Bool.self, forKey: .bpmPrecisionMode) ?? false,
            autoResumeAfterInterruption: try c.decodeIfPresent(Bool.self, forKey: .autoResumeAfterInterruption) ?? false,
            clickSound: try c.decodeIfPresent(ClickSound.self, forKey: .clickSound) ?? .digitalBeep,
            midiClockEnabled: try c.decodeIfPresent(Bool.self, forKey: .midiClockEnabled) ?? false,
            midiClockReceiveEnabled: try c.decodeIfPresent(Bool.self, forKey: .midiClockReceiveEnabled) ?? false,
            voiceCountMode: try c.decodeIfPresent(VoiceCountMode.self, forKey: .voiceCountMode) ?? .off,
            randomMutePercentage: try c.decodeIfPresent(Int.self, forKey: .randomMutePercentage) ?? 0,
            hapticMode: try c.decodeIfPresent(HapticMode.self, forKey: .hapticMode) ?? .off,
            hapticIntensity: try c.decodeIfPresent(HapticIntensity.self, forKey: .hapticIntensity) ?? HapticIntensity(),
            keepScreenAwakeDuringPlayback: try c.decodeIfPresent(Bool.self, forKey: .keepScreenAwakeDuringPlayback) ?? true
        )
    }
}
