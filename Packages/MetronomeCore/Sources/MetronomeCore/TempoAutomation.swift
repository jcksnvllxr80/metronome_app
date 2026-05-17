import Foundation

/// Linear tempo ramp from `startBPM` to `endBPM` over a fixed duration,
/// per spec §6.3 ("Gradual tempo change: accelerando / ritardando").
///
/// Step changes and ramp loops (also §6.3) are out of scope for v1.
///
/// The curve is **linear in time**: BPM(t) = startBPM + slope · t, where
/// slope = (endBPM − startBPM) / rampSeconds. Click times are computed by
/// inverting the integral of BPM(t)/60 — i.e. each click's wall-clock
/// position is solved directly from the curve, not stepped from a moving
/// "current BPM." This is what gives the ramp drift-free behavior the same
/// way constant-BPM scheduling has it.
///
/// `Duration.measures` is converted internally to seconds using
/// D · (startBPM + endBPM) / 120 = totalBeats — i.e. the average tempo
/// over the ramp determines how long N measures actually take.
public struct TempoAutomation: Hashable, Sendable {
    /// How the ramp's length is specified by the user.
    public enum Duration: Hashable, Sendable {
        /// Ramp completes after `n` measures of the song (post count-in).
        case measures(Int)
        /// Ramp completes after `s` seconds of the song (post count-in).
        case seconds(TimeInterval)
    }

    public let startBPM: BPM
    public let endBPM: BPM
    public let duration: Duration

    /// Returns `nil` if duration is non-positive. `startBPM == endBPM` is
    /// allowed (no-op ramp) — useful for the editor flow where the user is
    /// mid-edit.
    public init?(startBPM: BPM, endBPM: BPM, duration: Duration) {
        switch duration {
        case .measures(let m): guard m > 0 else { return nil }
        case .seconds(let s): guard s > 0 else { return nil }
        }
        self.startBPM = startBPM
        self.endBPM = endBPM
        self.duration = duration
    }

    /// Threshold below which `startBPM` and `endBPM` are treated as equal
    /// — avoids dividing by a near-zero slope in the quadratic inverse.
    /// 0.1 BPM matches BPM precision so we never trip this on a real edit.
    private static let flatThreshold: Double = 0.1

    /// Total beats covered by the ramp (post count-in).
    public func rampBeats(timeSignature: TimeSignature) -> Double {
        switch duration {
        case .measures(let m):
            return Double(m * timeSignature.numerator)
        case .seconds(let s):
            return s * (startBPM.value + endBPM.value) / 120
        }
    }

    /// Wall-clock seconds the ramp takes to complete.
    public func rampSeconds(timeSignature: TimeSignature) -> TimeInterval {
        switch duration {
        case .seconds(let s):
            return s
        case .measures(let m):
            let totalBeats = Double(m * timeSignature.numerator)
            // From the integral identity: D · (BPM₀ + BPM₁) / 120 = totalBeats
            return totalBeats * 120 / (startBPM.value + endBPM.value)
        }
    }

    /// Beats elapsed by `t` seconds from the start of the ramp.
    /// For `t` past the end of the ramp, tempo is constant at `endBPM`.
    public func beatPosition(forTime t: TimeInterval, timeSignature: TimeSignature) -> Double {
        let D = rampSeconds(timeSignature: timeSignature)
        if t <= D {
            if abs(startBPM.value - endBPM.value) < Self.flatThreshold {
                return startBPM.value * t / 60
            }
            let slope = (endBPM.value - startBPM.value) / D
            return (startBPM.value * t + slope * t * t / 2) / 60
        } else {
            let rampBeats = self.rampBeats(timeSignature: timeSignature)
            return rampBeats + endBPM.value * (t - D) / 60
        }
    }

    /// Wall-clock seconds at which the given beat position occurs, measured
    /// from the start of the ramp. `beat` may be fractional (e.g. 2.5 for
    /// an eighth-note subdivision halfway between beats 2 and 3).
    public func time(forBeatPosition beat: Double, timeSignature: TimeSignature) -> TimeInterval {
        precondition(beat >= 0, "Beat position must be non-negative")
        let rampBeats = self.rampBeats(timeSignature: timeSignature)
        if beat <= rampBeats {
            let D = rampSeconds(timeSignature: timeSignature)
            if abs(startBPM.value - endBPM.value) < Self.flatThreshold {
                return 60 * beat / startBPM.value
            }
            // Solve (slope/2) t² + startBPM t − 60·beat = 0 for t.
            // Pick the smaller positive root via the `+sqrt` form — works
            // for both accelerando (slope > 0) and ritardando (slope < 0),
            // see test cases.
            let slope = (endBPM.value - startBPM.value) / D
            let discriminant = startBPM.value * startBPM.value + 2 * slope * 60 * beat
            return (-startBPM.value + discriminant.squareRoot()) / slope
        } else {
            let D = rampSeconds(timeSignature: timeSignature)
            return D + (beat - rampBeats) * 60 / endBPM.value
        }
    }
}

// MARK: - Codable

extension TempoAutomation: Codable {
    private enum DurationKind: String, Codable {
        case measures, seconds
    }

    private enum CodingKeys: String, CodingKey {
        case startBPM, endBPM, durationKind, durationValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let start = try c.decode(BPM.self, forKey: .startBPM)
        let end = try c.decode(BPM.self, forKey: .endBPM)
        let kind = try c.decode(DurationKind.self, forKey: .durationKind)
        let duration: Duration
        switch kind {
        case .measures:
            duration = .measures(try c.decode(Int.self, forKey: .durationValue))
        case .seconds:
            duration = .seconds(try c.decode(TimeInterval.self, forKey: .durationValue))
        }
        guard let auto = TempoAutomation(startBPM: start, endBPM: end, duration: duration) else {
            throw DecodingError.dataCorruptedError(
                forKey: .durationValue,
                in: c,
                debugDescription: "Duration must be positive"
            )
        }
        self = auto
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startBPM, forKey: .startBPM)
        try c.encode(endBPM, forKey: .endBPM)
        switch duration {
        case .measures(let m):
            try c.encode(DurationKind.measures, forKey: .durationKind)
            try c.encode(m, forKey: .durationValue)
        case .seconds(let s):
            try c.encode(DurationKind.seconds, forKey: .durationKind)
            try c.encode(s, forKey: .durationValue)
        }
    }
}
