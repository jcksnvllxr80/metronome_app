import Testing
import Foundation
@testable import MetronomeCore

@Test func emptyEstimatorHasNoEstimate() {
    let est = TapTempoEstimator()
    #expect(est.estimate == nil)
    #expect(est.taps.isEmpty)
}

@Test func singleTapStillHasNoEstimate() {
    var est = TapTempoEstimator()
    let result = est.tap(at: 0)
    #expect(result == nil)
    #expect(est.taps == [0])
}

@Test func twoTapsAtHalfSecondGive120BPM() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    let result = est.tap(at: 0.5)
    #expect(result == BPM(120))
}

@Test func twoTapsAtOneSecondGive60BPM() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    let result = est.tap(at: 1.0)
    #expect(result == BPM(60))
}

@Test func threeEvenlySpacedTapsAverageCorrectly() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    _ = est.tap(at: 0.5)
    let result = est.tap(at: 1.0)
    // (0.5 + 0.5) / 2 = 0.5 → 120 BPM
    #expect(result == BPM(120))
}

@Test func fourTapsKeepsAllInWindow() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    _ = est.tap(at: 0.5)
    _ = est.tap(at: 1.0)
    _ = est.tap(at: 1.5)
    #expect(est.taps.count == 4)
    #expect(est.estimate == BPM(120))
}

@Test func fifthTapDropsOldestFromWindow() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)   // dropped after fifth
    _ = est.tap(at: 0.5)
    _ = est.tap(at: 1.0)
    _ = est.tap(at: 1.5)
    _ = est.tap(at: 2.0)
    #expect(est.taps.count == 4)
    #expect(est.taps.first == 0.5)
    #expect(est.estimate == BPM(120))
}

@Test func inactivityResetsWindow() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    _ = est.tap(at: 0.5)
    // > 2 s of silence
    let resetResult = est.tap(at: 3.0)
    // After reset, this tap is the first of a new measurement
    #expect(resetResult == nil)
    #expect(est.taps == [3.0])
}

@Test func inactivityThresholdIsExclusive() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    // Exactly 2.0s — NOT past the threshold (>, not >=)
    let result = est.tap(at: 2.0)
    #expect(result == BPM(30))
    #expect(est.taps.count == 2)
}

@Test func justOverTwoSecondsResetsWindow() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    let result = est.tap(at: 2.001)
    #expect(result == nil)
    #expect(est.taps == [2.001])
}

@Test func resetClearsState() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    _ = est.tap(at: 0.5)
    est.reset()
    #expect(est.taps.isEmpty)
    #expect(est.estimate == nil)
}

@Test func ultraFastTapsClampToMaxBPM() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    let result = est.tap(at: 0.1) // 600 BPM raw → clamps to 400
    #expect(result == BPM(BPM.maximum))
}

@Test func ultraSlowTapsClampToMinBPM() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    let result = est.tap(at: 5.0) // 12 BPM raw, but inactivity resets first
    // Actually 5.0 > 2.0 → resets, so estimate is nil
    #expect(result == nil)
}

@Test func slowButValidTapsClampLowEnd() {
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    // 1.9s gap → 31.6 BPM raw, stays in window
    let result = est.tap(at: 1.9)
    #expect(result != nil)
    // 60 / 1.9 ≈ 31.58, snapped to 0.1 = 31.6
    #expect(result!.value == 31.6)
}
