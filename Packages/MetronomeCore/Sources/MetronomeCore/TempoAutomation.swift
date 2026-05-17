import Foundation

/// Tempo automation for §6.3 (gradual ramp) + §6.4 (step) practice modes.
///
/// `.gradual` — linear BPM(t) curve from `start` to `end` over `duration`.
/// Click times are solved directly from the integral, so drift-free across
/// the full ramp.
///
/// `.step` — piecewise-constant BPM that jumps by `increment` every
/// `measuresPerStep` measures, optionally capped at `ceiling`. Past the
/// ceiling, BPM holds constant (the engine can choose to stop playback
/// when the ceiling is reached; the schedule math just clamps).
///
/// `Duration.measures` is converted internally to seconds when needed —
/// for gradual mode that uses the ramp's average BPM; for step mode each
/// measure runs at its step's constant BPM.
///
/// Ramp loops (the third §6.3 sub-feature) will slot in as a third case.
public enum TempoAutomation: Hashable, Sendable {
    /// Gradual accelerando / ritardando.
    case gradual(Gradual)
    /// Step changes, optionally with a BPM ceiling.
    case step(Step)

    public struct Gradual: Hashable, Sendable {
        public var startBPM: BPM
        public var endBPM: BPM
        public var duration: Duration

        public init(startBPM: BPM, endBPM: BPM, duration: Duration) {
            self.startBPM = startBPM
            self.endBPM = endBPM
            self.duration = duration
        }
    }

    public struct Step: Hashable, Sendable {
        public var startBPM: BPM
        /// Positive BPM delta added at each step boundary. Typed as
        /// `Double` (not `BPM`) because a delta isn't an absolute tempo
        /// — small values like 5 are common, but `BPM(5)` would clamp to
        /// `BPM.minimum` (20) and silently corrupt the semantics. Floored
        /// to 1 in init; spec §6.4 implies step mode always ascends.
        public var increment: Double
        /// Measure count between steps. Must be >= 1.
        public var measuresPerStep: Int
        /// Optional BPM ceiling. When reached, BPM holds constant and
        /// the engine can stop playback (handled at a higher layer).
        public var ceiling: BPM?

        public init(startBPM: BPM, increment: Double, measuresPerStep: Int, ceiling: BPM? = nil) {
            self.startBPM = startBPM
            self.increment = max(1, increment)
            self.measuresPerStep = max(1, measuresPerStep)
            self.ceiling = ceiling
        }

        /// BPM at the given step index (step 0 is the starting tempo).
        /// Clamps at `ceiling` when set.
        public func bpm(atStep step: Int) -> BPM {
            let raw = startBPM.value + Double(step) * increment
            if let ceiling = ceiling {
                return BPM(min(raw, ceiling.value))
            }
            return BPM(raw)
        }

        /// Step index that would be reached at the given beat position.
        /// Each step contains `measuresPerStep * numerator` beats.
        public func step(atBeat beat: Double, timeSignature: TimeSignature) -> Int {
            let beatsPerStep = Double(measuresPerStep * timeSignature.numerator)
            return Int((beat / beatsPerStep).rounded(.down))
        }

        /// Whether the ceiling has been hit for the given step index.
        /// Engines can use this to stop playback when the user's target
        /// tempo has been reached.
        public func ceilingReached(atStep step: Int) -> Bool {
            guard let ceiling = ceiling else { return false }
            let raw = startBPM.value + Double(step) * increment
            return raw >= ceiling.value
        }
    }

    public enum Duration: Hashable, Sendable {
        case measures(Int)
        case seconds(TimeInterval)
    }

    /// Initial tempo (used to lock `Song.bpm` when automation is active).
    public var startBPM: BPM {
        switch self {
        case .gradual(let g): return g.startBPM
        case .step(let s): return s.startBPM
        }
    }

    // MARK: - Factory inits with validation (return nil on bad input)

    public static func gradual(startBPM: BPM, endBPM: BPM, duration: Duration) -> TempoAutomation? {
        switch duration {
        case .measures(let m): guard m > 0 else { return nil }
        case .seconds(let s): guard s > 0 else { return nil }
        }
        return .gradual(Gradual(startBPM: startBPM, endBPM: endBPM, duration: duration))
    }

    public static func step(
        startBPM: BPM,
        increment: Double,
        measuresPerStep: Int,
        ceiling: BPM? = nil
    ) -> TempoAutomation? {
        guard measuresPerStep > 0 else { return nil }
        guard increment > 0 else { return nil }
        if let ceiling = ceiling, ceiling.value <= startBPM.value { return nil }
        return .step(Step(
            startBPM: startBPM,
            increment: increment,
            measuresPerStep: measuresPerStep,
            ceiling: ceiling
        ))
    }

    /// Threshold below which `startBPM` and `endBPM` of a gradual ramp
    /// are treated as equal — avoids dividing by near-zero slope.
    private static let flatThreshold: Double = 0.1

    // MARK: - Public helpers exposed for callers + tests

    /// Wall-clock seconds the ramp/step plan takes to finish. For
    /// gradual: end of the BPM curve. For step: total time until the
    /// ceiling is reached (or until startBPM + N*increment first equals
    /// or exceeds ceiling); returns nil for step without a ceiling
    /// (the schedule continues indefinitely).
    public func rampSeconds(timeSignature: TimeSignature) -> TimeInterval? {
        switch self {
        case .gradual(let g):
            return Self.gradualRampSeconds(g, timeSignature: timeSignature)
        case .step(let s):
            guard s.ceiling != nil else { return nil }
            // Steps needed: ceil((ceiling - start) / increment). Each step
            // is `measuresPerStep * numerator` beats at that step's BPM.
            var t = 0.0
            let beatsPerStep = Double(s.measuresPerStep * timeSignature.numerator)
            var idx = 0
            while !s.ceilingReached(atStep: idx) {
                let bpm = s.bpm(atStep: idx)
                t += beatsPerStep * (60.0 / bpm.value)
                idx += 1
                if idx > 10_000 { return nil } // safety
            }
            return t
        }
    }

    /// Total beats covered by the ramp/step plan. Same nil semantics as
    /// `rampSeconds(timeSignature:)`.
    public func rampBeats(timeSignature: TimeSignature) -> Double? {
        switch self {
        case .gradual(let g):
            return Self.gradualRampBeats(g, timeSignature: timeSignature)
        case .step(let s):
            guard s.ceiling != nil else { return nil }
            let beatsPerStep = Double(s.measuresPerStep * timeSignature.numerator)
            var idx = 0
            while !s.ceilingReached(atStep: idx) {
                idx += 1
                if idx > 10_000 { return nil }
            }
            return beatsPerStep * Double(idx)
        }
    }

    // MARK: - Schedule math

    /// Beats elapsed by `t` seconds from the start of the song (post
    /// count-in). For `t` past the end of a ramp/ceiling, tempo holds
    /// constant at the terminal BPM.
    public func beatPosition(forTime t: TimeInterval, timeSignature: TimeSignature) -> Double {
        switch self {
        case .gradual(let g):
            return Self.gradualBeatPosition(g, t: t, timeSignature: timeSignature)
        case .step(let s):
            return Self.stepBeatPosition(s, t: t, timeSignature: timeSignature)
        }
    }

    /// Wall-clock seconds at which the given beat position occurs (from
    /// the start of the song, post count-in). `beat` may be fractional.
    public func time(forBeatPosition beat: Double, timeSignature: TimeSignature) -> TimeInterval {
        precondition(beat >= 0, "Beat position must be non-negative")
        switch self {
        case .gradual(let g):
            return Self.gradualTime(g, beat: beat, timeSignature: timeSignature)
        case .step(let s):
            return Self.stepTime(s, beat: beat, timeSignature: timeSignature)
        }
    }

    // MARK: - Gradual math (unchanged from the pre-refactor implementation)

    private static func gradualRampSeconds(_ g: Gradual, timeSignature: TimeSignature) -> TimeInterval {
        switch g.duration {
        case .seconds(let s): return s
        case .measures(let m):
            let totalBeats = Double(m * timeSignature.numerator)
            return totalBeats * 120 / (g.startBPM.value + g.endBPM.value)
        }
    }

    private static func gradualRampBeats(_ g: Gradual, timeSignature: TimeSignature) -> Double {
        switch g.duration {
        case .measures(let m): return Double(m * timeSignature.numerator)
        case .seconds(let s): return s * (g.startBPM.value + g.endBPM.value) / 120
        }
    }

    private static func gradualBeatPosition(_ g: Gradual, t: TimeInterval, timeSignature: TimeSignature) -> Double {
        let D = gradualRampSeconds(g, timeSignature: timeSignature)
        if t <= D {
            if abs(g.startBPM.value - g.endBPM.value) < flatThreshold {
                return g.startBPM.value * t / 60
            }
            let slope = (g.endBPM.value - g.startBPM.value) / D
            return (g.startBPM.value * t + slope * t * t / 2) / 60
        }
        let rampBeats = gradualRampBeats(g, timeSignature: timeSignature)
        return rampBeats + g.endBPM.value * (t - D) / 60
    }

    private static func gradualTime(_ g: Gradual, beat: Double, timeSignature: TimeSignature) -> TimeInterval {
        let rampBeats = gradualRampBeats(g, timeSignature: timeSignature)
        if beat <= rampBeats {
            let D = gradualRampSeconds(g, timeSignature: timeSignature)
            if abs(g.startBPM.value - g.endBPM.value) < flatThreshold {
                return 60 * beat / g.startBPM.value
            }
            let slope = (g.endBPM.value - g.startBPM.value) / D
            let discriminant = g.startBPM.value * g.startBPM.value + 2 * slope * 60 * beat
            return (-g.startBPM.value + discriminant.squareRoot()) / slope
        }
        let D = gradualRampSeconds(g, timeSignature: timeSignature)
        return D + (beat - rampBeats) * 60 / g.endBPM.value
    }

    // MARK: - Step math (piecewise constant BPM)

    private static func stepBeatPosition(_ s: Step, t: TimeInterval, timeSignature: TimeSignature) -> Double {
        let beatsPerStep = Double(s.measuresPerStep * timeSignature.numerator)
        var timeLeft = t
        var beats = 0.0
        var idx = 0
        while timeLeft > 0 {
            let bpm = s.bpm(atStep: idx)
            let secondsPerBeat = 60.0 / bpm.value
            let stepDuration = beatsPerStep * secondsPerBeat
            // Once ceiling is reached, the BPM is constant forever — short-circuit.
            if s.ceilingReached(atStep: idx) {
                return beats + timeLeft / secondsPerBeat
            }
            if timeLeft <= stepDuration {
                return beats + timeLeft / secondsPerBeat
            }
            beats += beatsPerStep
            timeLeft -= stepDuration
            idx += 1
        }
        return beats
    }

    private static func stepTime(_ s: Step, beat: Double, timeSignature: TimeSignature) -> TimeInterval {
        let beatsPerStep = Double(s.measuresPerStep * timeSignature.numerator)
        var beatsLeft = beat
        var time = 0.0
        var idx = 0
        while beatsLeft > 0 {
            let bpm = s.bpm(atStep: idx)
            let secondsPerBeat = 60.0 / bpm.value
            // After the ceiling, time accrues linearly forever.
            if s.ceilingReached(atStep: idx) {
                return time + beatsLeft * secondsPerBeat
            }
            if beatsLeft <= beatsPerStep {
                return time + beatsLeft * secondsPerBeat
            }
            time += beatsPerStep * secondsPerBeat
            beatsLeft -= beatsPerStep
            idx += 1
        }
        return time
    }
}

// MARK: - Codable

extension TempoAutomation: Codable {
    private enum Kind: String, Codable {
        case gradual, step
    }
    private enum DurationKind: String, Codable {
        case measures, seconds
    }
    private enum CodingKeys: String, CodingKey {
        // Common
        case kind, startBPM
        // Gradual
        case endBPM, durationKind, durationValue
        // Step
        case increment, measuresPerStep, ceiling
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy decode: pre-refactor JSON had no `kind` field; treat as gradual.
        let kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .gradual
        let start = try c.decode(BPM.self, forKey: .startBPM)
        switch kind {
        case .gradual:
            let end = try c.decode(BPM.self, forKey: .endBPM)
            let dKind = try c.decode(DurationKind.self, forKey: .durationKind)
            let duration: Duration
            switch dKind {
            case .measures: duration = .measures(try c.decode(Int.self, forKey: .durationValue))
            case .seconds: duration = .seconds(try c.decode(TimeInterval.self, forKey: .durationValue))
            }
            guard let auto = TempoAutomation.gradual(startBPM: start, endBPM: end, duration: duration) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .durationValue, in: c,
                    debugDescription: "Duration must be positive"
                )
            }
            self = auto
        case .step:
            let increment = try c.decode(Double.self, forKey: .increment)
            let measuresPerStep = try c.decode(Int.self, forKey: .measuresPerStep)
            let ceiling = try c.decodeIfPresent(BPM.self, forKey: .ceiling)
            guard let auto = TempoAutomation.step(
                startBPM: start,
                increment: increment,
                measuresPerStep: measuresPerStep,
                ceiling: ceiling
            ) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .measuresPerStep, in: c,
                    debugDescription: "measuresPerStep must be > 0 and ceiling must exceed startBPM"
                )
            }
            self = auto
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .gradual(let g):
            try c.encode(Kind.gradual, forKey: .kind)
            try c.encode(g.startBPM, forKey: .startBPM)
            try c.encode(g.endBPM, forKey: .endBPM)
            switch g.duration {
            case .measures(let m):
                try c.encode(DurationKind.measures, forKey: .durationKind)
                try c.encode(m, forKey: .durationValue)
            case .seconds(let s):
                try c.encode(DurationKind.seconds, forKey: .durationKind)
                try c.encode(s, forKey: .durationValue)
            }
        case .step(let s):
            try c.encode(Kind.step, forKey: .kind)
            try c.encode(s.startBPM, forKey: .startBPM)
            try c.encode(s.increment, forKey: .increment)
            try c.encode(s.measuresPerStep, forKey: .measuresPerStep)
            try c.encodeIfPresent(s.ceiling, forKey: .ceiling)
        }
    }
}
