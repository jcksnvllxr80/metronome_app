import Foundation

/// Same-measure polyrhythm configuration (spec §2.4). When attached to
/// a `ClickSchedule`, fires `pulses` evenly-spaced clicks per measure
/// of the primary meter — e.g. with `pulses == 3` against a 4/4 meter
/// you get the classic 3-against-4 cross-rhythm. The polyrhythm clicks
/// share the primary meter's measure boundary; they don't have their
/// own BPM. Each measure's pulse period is `measureDuration / pulses`,
/// so tempo automation that varies measure durations stays in sync.
///
/// Polyrhythm clicks don't carry beat indices or accent patterns —
/// they're a flat stream marking the secondary subdivision. They use
/// their own `sound` and `volume` so they're audibly distinct from
/// the primary meter.
///
/// Disabling: an `EngineSettings.polyrhythm` of `nil` means polyrhythm
/// is off — no parallel clicks, no second stream. A non-nil config with
/// `pulses == 1` is structurally equivalent to "off" and is rejected at
/// init (clamped to `pulses >= 2`).
public struct PolyrhythmConfig: Hashable, Sendable, Codable {
    /// Allowed range for `pulses`. Per spec §2.4 the polyrhythm is a
    /// secondary subdivision of the primary measure — anything outside
    /// 2–12 either degenerates (1 = no polyrhythm) or stops being
    /// musically useful (13+ approaches a buzz).
    public static let pulsesRange: ClosedRange<Int> = 2...12

    /// Number of evenly-spaced clicks per primary-meter measure.
    /// Clamped to `pulsesRange` on init.
    public let pulses: Int
    /// Sound for the polyrhythm clicks. Distinct from the primary
    /// `EngineSettings.clickSound` so the two streams are audibly
    /// separable.
    public let sound: ClickSound
    /// 0.0–1.0 volume multiplier for the polyrhythm stream. Clamped
    /// at init. The audio scheduler multiplies this with
    /// `EngineSettings.masterVolume` at output time.
    public let volume: Double

    public init(
        pulses: Int = 3,
        sound: ClickSound = .cowbell,
        volume: Double = 0.8
    ) {
        self.pulses = max(Self.pulsesRange.lowerBound, min(Self.pulsesRange.upperBound, pulses))
        self.sound = sound
        self.volume = max(0, min(1, volume))
    }
}
