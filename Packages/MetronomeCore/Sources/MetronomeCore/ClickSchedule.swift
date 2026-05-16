import Foundation

/// Pure value-type that computes the click sequence for a given tempo /
/// time signature / subdivision / accent pattern, anchored at `startTime`.
///
/// Separating the math from `MetronomeEngine` makes it testable without
/// concurrency, audio, or wall-clock time. The engine owns one of these
/// and re-creates it whenever the user changes tempo, meter, subdivision,
/// or accent pattern.
///
/// Drift behavior: every click time is computed from
/// `startTime + index * clickPeriod`. Errors do not accumulate — the
/// scheduler can run for hours without drift exceeding the spec's
/// < 1 ms/minute budget, as long as `startTime` is captured from a
/// monotonic source (`SystemClock` / `mach_absolute_time`).
///
/// Count-in: when `countInMeasures > 0`, the first
/// `countInMeasures * clicksPerMeasure` clicks are flagged `isCountIn`
/// and use the default accent rule (downbeat + normals) instead of the
/// active `AccentPattern`. After count-in ends, the pattern kicks in.
public struct ClickSchedule: Hashable, Sendable {
    public let bpm: BPM
    public let timeSignature: TimeSignature
    public let subdivision: Subdivision
    public let startTime: TimeInterval
    public let accentPattern: AccentPattern?
    public let countInMeasures: Int

    /// Precondition: if `accentPattern` is non-nil, its `timeSignature` must
    /// equal `timeSignature`. The caller (engine) clears mismatched patterns
    /// when the time signature changes; constructing a `ClickSchedule` with
    /// a mismatch is a programmer error. `countInMeasures` must be >= 0.
    public init(
        bpm: BPM,
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        startTime: TimeInterval,
        accentPattern: AccentPattern? = nil,
        countInMeasures: Int = 0
    ) {
        if let pattern = accentPattern {
            precondition(
                pattern.timeSignature == timeSignature,
                "AccentPattern's time signature must match the schedule's"
            )
        }
        precondition(countInMeasures >= 0, "countInMeasures must be non-negative")
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.subdivision = subdivision
        self.startTime = startTime
        self.accentPattern = accentPattern
        self.countInMeasures = countInMeasures
    }

    /// Seconds between consecutive clicks (including subdivision clicks).
    public var clickPeriod: TimeInterval {
        bpm.beatPeriod / Double(subdivision.partsPerBeat)
    }

    /// Total clicks per measure (numerator × parts-per-beat).
    public var clicksPerMeasure: Int {
        timeSignature.numerator * subdivision.partsPerBeat
    }

    /// Number of clicks the count-in occupies (0 when count-in is off).
    public var countInClicks: Int {
        countInMeasures * clicksPerMeasure
    }

    /// Compute the Nth click since `startTime`. `index` is 0-based.
    public func click(at index: Int) -> Click {
        precondition(index >= 0, "Click index must be non-negative")
        let time = startTime + Double(index) * clickPeriod
        let isCountIn = index < countInClicks

        // Count-in math uses its own measure counting (so the first count-in
        // click is measure 0 of the count-in, not of the song).
        let positionForLayout: Int
        let measureIndex: Int
        if isCountIn {
            positionForLayout = index % clicksPerMeasure
            measureIndex = index / clicksPerMeasure
        } else {
            let songIndex = index - countInClicks
            positionForLayout = songIndex % clicksPerMeasure
            measureIndex = songIndex / clicksPerMeasure
        }
        let beatIndex = positionForLayout / subdivision.partsPerBeat
        let subdivisionIndex = positionForLayout % subdivision.partsPerBeat

        // Subdivisions don't pick up the parent beat's overrides — they're
        // grayscale defaults. Only main beats (sub == 0) consult the pattern.
        // Count-in clicks always use the default rule, never the pattern.
        if subdivisionIndex == 0 {
            let cfg: BeatConfig
            if isCountIn {
                cfg = defaultBeatConfig(beat: beatIndex)
            } else {
                cfg = accentPattern?.config(forBeat: beatIndex)
                    ?? defaultBeatConfig(beat: beatIndex)
            }
            return Click(
                beatIndex: beatIndex,
                subdivisionIndex: subdivisionIndex,
                measureIndex: measureIndex,
                time: time,
                accent: cfg.accent,
                soundOverride: cfg.soundOverride,
                pitchShift: cfg.pitchShift,
                isCountIn: isCountIn
            )
        } else {
            return Click(
                beatIndex: beatIndex,
                subdivisionIndex: subdivisionIndex,
                measureIndex: measureIndex,
                time: time,
                accent: .soft,
                soundOverride: nil,
                pitchShift: .unison,
                isCountIn: isCountIn
            )
        }
    }

    /// Index of the first click at or after `time`. If `time` falls before
    /// `startTime`, returns 0 (the very first click).
    public func firstClickIndex(atOrAfter time: TimeInterval) -> Int {
        guard time > startTime else { return 0 }
        let elapsed = time - startTime
        let raw = elapsed / clickPeriod
        return Int(raw.rounded(.up))
    }

    /// Returns `count` consecutive clicks starting at or after `time`.
    public func clicks(from time: TimeInterval, count: Int) -> [Click] {
        precondition(count >= 0, "Click count must be non-negative")
        let start = firstClickIndex(atOrAfter: time)
        return (0..<count).map { click(at: start + $0) }
    }

    /// Fallback BeatConfig when no `AccentPattern` is active: downbeat is
    /// `.accent`, all other main beats `.normal`. Also used for every
    /// count-in main-beat click.
    private func defaultBeatConfig(beat: Int) -> BeatConfig {
        beat == 0 ? .downbeat : .mainBeat
    }
}
