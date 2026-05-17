import Testing
import Foundation
@testable import MetronomeCore

// MARK: - PolyrhythmConfig clamping

@Test func polyConfigClampsPulsesBelowRange() {
    let p = PolyrhythmConfig(pulses: 1)
    #expect(p.pulses == PolyrhythmConfig.pulsesRange.lowerBound)
}

@Test func polyConfigClampsPulsesAboveRange() {
    let p = PolyrhythmConfig(pulses: 99)
    #expect(p.pulses == PolyrhythmConfig.pulsesRange.upperBound)
}

@Test func polyConfigClampsVolume() {
    let high = PolyrhythmConfig(pulses: 3, volume: 1.5)
    let low = PolyrhythmConfig(pulses: 3, volume: -0.2)
    #expect(high.volume == 1.0)
    #expect(low.volume == 0.0)
}

// MARK: - ClickSchedule.polyClick math (no automation)

@Test func polyClickReturnsNilWhenDisabled() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    #expect(s.polyClick(at: 0) == nil)
}

@Test func polyClickFirstAlignsWithDownbeat() {
    // 3:4 polyrhythm at 120 BPM 4/4: measure = 2.0s, pulse 0 at 0.0s.
    let poly = PolyrhythmConfig(pulses: 3)
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .none,
        startTime: 10.0, polyrhythm: poly
    )
    let pc = s.polyClick(at: 0)!
    #expect(pc.measureIndex == 0)
    #expect(pc.pulseIndex == 0)
    #expect(abs(pc.time - 10.0) < 1e-9)
}

@Test func polyClickEvenlySpacedAcrossMeasure() {
    // 3 against 4 at 120 BPM. Measure period = 4 beats × 0.5s = 2.0s.
    // Three pulses split that into 2.0/3 ≈ 0.6667s apart.
    let poly = PolyrhythmConfig(pulses: 3)
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .none,
        startTime: 0, polyrhythm: poly
    )
    let p0 = s.polyClick(at: 0)!
    let p1 = s.polyClick(at: 1)!
    let p2 = s.polyClick(at: 2)!
    let p3 = s.polyClick(at: 3)!
    #expect(abs(p0.time - 0.0) < 1e-9)
    #expect(abs(p1.time - (2.0 / 3.0)) < 1e-9)
    #expect(abs(p2.time - (4.0 / 3.0)) < 1e-9)
    // Measure boundary: pulse 3 = pulse 0 of measure 1 = at 2.0s.
    #expect(abs(p3.time - 2.0) < 1e-9)
    #expect(p3.measureIndex == 1)
    #expect(p3.pulseIndex == 0)
}

@Test func polyClickHonorsCountIn() {
    // 1 measure of count-in at 120 BPM 4/4 = 2.0s preamble. Polyrhythm
    // pulse 0 should fire AT the post-count-in downbeat (t=2.0), NOT
    // at startTime.
    let poly = PolyrhythmConfig(pulses: 3)
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .none,
        startTime: 0, countInMeasures: 1, polyrhythm: poly
    )
    let p0 = s.polyClick(at: 0)!
    #expect(abs(p0.time - 2.0) < 1e-9)
}

@Test func polyClickCarriesSoundAndVolume() {
    let poly = PolyrhythmConfig(pulses: 5, sound: .hiHat, volume: 0.6)
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .none,
        startTime: 0, polyrhythm: poly
    )
    let p = s.polyClick(at: 2)!
    #expect(p.sound == .hiHat)
    #expect(abs(p.volume - 0.6) < 1e-12)
}

// MARK: - polyClick measure indexing

@Test func polyClickMeasureAndPulseIndices() {
    let poly = PolyrhythmConfig(pulses: 5)
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .none,
        startTime: 0, polyrhythm: poly
    )
    // 5 pulses per measure: index 7 = measure 1, pulse 2.
    let p = s.polyClick(at: 7)!
    #expect(p.measureIndex == 1)
    #expect(p.pulseIndex == 2)
}

// MARK: - firstPolyClickIndex(atOrAfter:)

@Test func firstPolyClickAtStartReturnsZero() {
    let poly = PolyrhythmConfig(pulses: 3)
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .none,
        startTime: 10, polyrhythm: poly
    )
    #expect(s.firstPolyClickIndex(atOrAfter: 5.0) == 0)
    #expect(s.firstPolyClickIndex(atOrAfter: 10.0) == 0)
}

@Test func firstPolyClickInsideMeasure() {
    // 3:4 at 120 BPM, measure 2.0s. Pulses at 0.0, 0.667, 1.333.
    // At t=1.0, next pulse is index 2 (1.333s).
    let poly = PolyrhythmConfig(pulses: 3)
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .none,
        startTime: 0, polyrhythm: poly
    )
    #expect(s.firstPolyClickIndex(atOrAfter: 1.0) == 2)
}

@Test func polyClicksFromReturnsCorrectStream() {
    let poly = PolyrhythmConfig(pulses: 3)
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .fourFour, subdivision: .none,
        startTime: 0, polyrhythm: poly
    )
    let pcs = s.polyClicks(from: 0, count: 6)
    #expect(pcs.count == 6)
    #expect(pcs[0].pulseIndex == 0 && pcs[0].measureIndex == 0)
    #expect(pcs[3].pulseIndex == 0 && pcs[3].measureIndex == 1)
    #expect(pcs[5].pulseIndex == 2 && pcs[5].measureIndex == 1)
}

@Test func polyClicksFromEmptyWhenDisabled() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    #expect(s.polyClicks(from: 0, count: 10).isEmpty)
}

// MARK: - polyClick under odd meter

@Test func polyClickAgainstSevenEight() {
    // 5 against 7/8 at 120 BPM. 7/8 measure period = 7 × 0.25s = 1.75s
    // (denominator 8 → beat is an eighth note → period bpm.beatPeriod / 2).
    // Wait — bpm.beatPeriod is the quarter-note period (0.5s at 120 BPM).
    // The schedule treats the numerator as beats regardless of denominator
    // for measure duration: 7 × 0.5s = 3.5s.
    // 5 pulses across 3.5s → 0.7s apart.
    let poly = PolyrhythmConfig(pulses: 5)
    let s = ClickSchedule(
        bpm: BPM(120), timeSignature: .sevenEight, subdivision: .none,
        startTime: 0, polyrhythm: poly
    )
    let p0 = s.polyClick(at: 0)!
    let p1 = s.polyClick(at: 1)!
    let p5 = s.polyClick(at: 5)!  // pulse 0 of measure 1
    #expect(abs(p0.time - 0.0) < 1e-9)
    #expect(abs(p1.time - 0.7) < 1e-9)
    #expect(abs(p5.time - 3.5) < 1e-9)
}
