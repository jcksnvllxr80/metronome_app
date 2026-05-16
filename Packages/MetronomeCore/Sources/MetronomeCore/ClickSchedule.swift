import Foundation

/// Pure value-type that computes the click sequence for a given tempo /
/// time signature / subdivision, anchored at `startTime`.
///
/// Separating the math from `MetronomeEngine` makes it testable without
/// concurrency, audio, or wall-clock time. The engine owns one of these
/// and re-creates it whenever the user changes tempo or meter.
///
/// Drift behavior: every click time is computed from
/// `startTime + index * clickPeriod`. Errors do not accumulate — the
/// scheduler can run for hours without drift exceeding the spec's
/// < 1 ms/minute budget, as long as `startTime` is captured from a
/// monotonic source (`SystemClock` / `mach_absolute_time`).
public struct ClickSchedule: Hashable, Sendable {
    public let bpm: BPM
    public let timeSignature: TimeSignature
    public let subdivision: Subdivision
    public let startTime: TimeInterval

    public init(
        bpm: BPM,
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        startTime: TimeInterval
    ) {
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.subdivision = subdivision
        self.startTime = startTime
    }

    /// Seconds between consecutive clicks (including subdivision clicks).
    public var clickPeriod: TimeInterval {
        bpm.beatPeriod / Double(subdivision.partsPerBeat)
    }

    /// Total clicks per measure (numerator × parts-per-beat).
    public var clicksPerMeasure: Int {
        timeSignature.numerator * subdivision.partsPerBeat
    }

    /// Compute the Nth click since `startTime`. `index` is 0-based.
    public func click(at index: Int) -> Click {
        precondition(index >= 0, "Click index must be non-negative")
        let time = startTime + Double(index) * clickPeriod
        let measureIndex = index / clicksPerMeasure
        let positionInMeasure = index % clicksPerMeasure
        let beatIndex = positionInMeasure / subdivision.partsPerBeat
        let subdivisionIndex = positionInMeasure % subdivision.partsPerBeat
        return Click(
            beatIndex: beatIndex,
            subdivisionIndex: subdivisionIndex,
            measureIndex: measureIndex,
            time: time,
            accent: defaultAccent(beat: beatIndex, sub: subdivisionIndex)
        )
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

    /// Default accent rule before user accent patterns are applied:
    /// downbeat → `.accent`, other main beats → `.normal`, subdivisions → `.soft`.
    /// Per-beat user overrides (spec §3) will replace this in a later pass.
    private func defaultAccent(beat: Int, sub: Int) -> AccentLevel {
        if beat == 0 && sub == 0 { return .accent }
        if sub == 0 { return .normal }
        return .soft
    }
}
