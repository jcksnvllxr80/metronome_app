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

// MARK: - v0.34.2 median + min-interval

@Test func tapTooCloseToPreviousIsRejected() {
    // 50ms after the previous tap (would be 1200 BPM raw) — should
    // be rejected by minimumInterval, leaving the window unchanged.
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    _ = est.tap(at: 0.5)  // estimate 120 BPM
    let result = est.tap(at: 0.55)  // 50ms after previous — rejected
    #expect(est.taps == [0, 0.5])  // window unchanged
    #expect(result == BPM(120))    // estimate unchanged
}

@Test func singleOutlierDoesNotWreckEstimate() {
    // Four taps with one short interval — mean would pull BPM way
    // up; median should hold at 120.
    //   intervals: 0.5, 0.2, 0.5 → sorted [0.2, 0.5, 0.5] → median 0.5
    // Mean would have been (0.5+0.2+0.5)/3 = 0.4 → 150 BPM.
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    _ = est.tap(at: 0.5)
    _ = est.tap(at: 0.7)  // outlier — way too fast
    let result = est.tap(at: 1.2)
    #expect(result == BPM(120))
}

@Test func twoIntervalsMedianIsTheirAverage() {
    // 3 taps → 2 intervals: 0.4, 0.6. Median of even-length list is
    // the average of the two middle values: (0.4 + 0.6) / 2 = 0.5
    // → 120 BPM. (Same as mean here; the test pins the even-length
    // branch.)
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    _ = est.tap(at: 0.4)
    let result = est.tap(at: 1.0)
    #expect(result == BPM(120))
}

@Test func minimumIntervalIsExclusive() {
    // Exactly 100ms after the previous tap — NOT rejected (< is
    // strict). 600 BPM raw → clamps to 400 BPM.
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    let result = est.tap(at: 0.1)
    #expect(est.taps == [0, 0.1])
    #expect(result == BPM(BPM.maximum))
}

@Test func rejectedTapDoesNotAdvanceLastTime() {
    // After a rejected tap, the NEXT tap measures from the previous
    // accepted tap, not from the rejected one. (i.e. rejection
    // doesn't poison the window.)
    var est = TapTempoEstimator()
    _ = est.tap(at: 0)
    _ = est.tap(at: 0.5)
    _ = est.tap(at: 0.55)  // rejected (50ms gap)
    let result = est.tap(at: 1.0)  // 500ms after 0.5 (last accepted)
    // Intervals: [0.5, 0.5] → median 0.5 → 120 BPM
    #expect(result == BPM(120))
}
