import Testing
import Foundation
@testable import MetronomeCore

// MARK: - Construction

@Test func rejectsNonPositiveMeasures() {
    #expect(TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .measures(0)) == nil)
    #expect(TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .measures(-1)) == nil)
}

@Test func rejectsNonPositiveSeconds() {
    #expect(TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .seconds(0)) == nil)
    #expect(TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .seconds(-1)) == nil)
}

@Test func allowsEqualStartAndEnd() {
    let a = TempoAutomation(startBPM: BPM(120), endBPM: BPM(120), duration: .measures(4))
    #expect(a != nil)
}

// MARK: - rampSeconds + rampBeats — measures ↔ seconds conversion

@Test func rampSecondsForMeasuresMode() {
    // 120 BPM constant, 4/4, 4 measures = 16 beats = 8 seconds
    let a = TempoAutomation(startBPM: BPM(120), endBPM: BPM(120), duration: .measures(4))!
    #expect(abs(a.rampSeconds(timeSignature: .fourFour) - 8.0) < 1e-9)
}

@Test func rampSecondsForVariableTempo() {
    // 60→120 over 4 measures of 4/4 = 16 beats
    // Average tempo = 90 BPM → 16 beats / 90 bpm = 16/1.5 = 10.6666… seconds
    let a = TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .measures(4))!
    let expected = 16.0 * 60.0 / 90.0
    #expect(abs(a.rampSeconds(timeSignature: .fourFour) - expected) < 1e-9)
}

@Test func rampBeatsForSecondsMode() {
    // 60→120 over 10s. Avg 90 BPM × 10s = 900 beats/min × 10/60 = 15 beats
    let a = TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .seconds(10))!
    #expect(abs(a.rampBeats(timeSignature: .fourFour) - 15.0) < 1e-9)
}

// MARK: - beatPosition(forTime:) — forward direction

@Test func beatPositionConstantTempo() {
    let a = TempoAutomation(startBPM: BPM(120), endBPM: BPM(120), duration: .seconds(10))!
    // At 120 BPM, 4 beats per 2 seconds
    #expect(abs(a.beatPosition(forTime: 2.0, timeSignature: .fourFour) - 4.0) < 1e-9)
}

@Test func beatPositionAccelerando() {
    // 60→120 over 10s. At t=5 (midpoint), BPM(t) ≈ 90.
    // Beats(5) = ∫₀⁵ (60+6t)/60 dt = (60·5 + 3·25)/60 = (300+75)/60 = 6.25
    let a = TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .seconds(10))!
    #expect(abs(a.beatPosition(forTime: 5.0, timeSignature: .fourFour) - 6.25) < 1e-9)
}

@Test func beatPositionRitardando() {
    // 120→60 over 10s. At t=5, by symmetry beats = 15 - 6.25 = 8.75
    let a = TempoAutomation(startBPM: BPM(120), endBPM: BPM(60), duration: .seconds(10))!
    #expect(abs(a.beatPosition(forTime: 5.0, timeSignature: .fourFour) - 8.75) < 1e-9)
}

@Test func beatPositionPastRamp() {
    // 60→120 over 10s, then constant 120. At t=15, ramp ended at 15 beats,
    // plus 5 more seconds at 120 BPM = 10 more beats → 25 beats total.
    let a = TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .seconds(10))!
    #expect(abs(a.beatPosition(forTime: 15.0, timeSignature: .fourFour) - 25.0) < 1e-9)
}

// MARK: - time(forBeatPosition:) — inverse

@Test func timeForBeatConstantTempo() {
    let a = TempoAutomation(startBPM: BPM(120), endBPM: BPM(120), duration: .seconds(10))!
    // Beat 4 at 120 BPM = 2 seconds
    #expect(abs(a.time(forBeatPosition: 4, timeSignature: .fourFour) - 2.0) < 1e-9)
}

@Test func timeForBeatAccelerando() {
    // 60→120 over 10s. Beat 6.25 should be at t=5 (inverse of forward test above)
    let a = TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .seconds(10))!
    #expect(abs(a.time(forBeatPosition: 6.25, timeSignature: .fourFour) - 5.0) < 1e-9)
}

@Test func timeForBeatRitardando() {
    // 120→60 over 10s. Beat 8.75 at t=5
    let a = TempoAutomation(startBPM: BPM(120), endBPM: BPM(60), duration: .seconds(10))!
    #expect(abs(a.time(forBeatPosition: 8.75, timeSignature: .fourFour) - 5.0) < 1e-9)
}

@Test func timeForBeatPastRamp() {
    // 60→120 over 10s, then constant. Beat 25 at t=15
    let a = TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .seconds(10))!
    #expect(abs(a.time(forBeatPosition: 25, timeSignature: .fourFour) - 15.0) < 1e-9)
}

@Test func forwardInverseRoundTrip() {
    // Forward then inverse should land where we started, across the whole ramp.
    let a = TempoAutomation(startBPM: BPM(80), endBPM: BPM(140), duration: .seconds(20))!
    for t in stride(from: 0.0, through: 25.0, by: 0.5) {
        let beats = a.beatPosition(forTime: t, timeSignature: .fourFour)
        let backToT = a.time(forBeatPosition: beats, timeSignature: .fourFour)
        #expect(abs(backToT - t) < 1e-6, "roundtrip failed at t=\(t)")
    }
}

// MARK: - Codable round-trip

@Test func codableMeasuresMode() throws {
    let a = TempoAutomation(startBPM: BPM(60), endBPM: BPM(180), duration: .measures(8))!
    let data = try JSONEncoder().encode(a)
    let b = try JSONDecoder().decode(TempoAutomation.self, from: data)
    #expect(b == a)
}

@Test func codableSecondsMode() throws {
    let a = TempoAutomation(startBPM: BPM(120), endBPM: BPM(60), duration: .seconds(30))!
    let data = try JSONEncoder().encode(a)
    let b = try JSONDecoder().decode(TempoAutomation.self, from: data)
    #expect(b == a)
}

@Test func codableRejectsZeroDuration() {
    // Hand-crafted payload with 0 seconds
    let json = """
    {"startBPM": 120, "endBPM": 60, "durationKind": "seconds", "durationValue": 0}
    """.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(TempoAutomation.self, from: json)
    }
}

// MARK: - Integration with ClickSchedule

@Test func clickScheduleHonorsAutomation() {
    // Ramp 60→120 over 4 measures of 4/4 (= 16 beats).
    // Total ramp seconds = 16 * 60 / 90 = 10.666… seconds.
    // Without automation, 16 beats at avg 90 would take the same wall time,
    // but click times along the way differ — early beats spread, late ones compress.
    let auto = TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .measures(4))!
    let s = ClickSchedule(
        bpm: BPM(60),
        timeSignature: .fourFour,
        subdivision: .none,
        startTime: 0,
        automation: auto
    )
    let beat0 = s.click(at: 0)
    let beat4 = s.click(at: 4)  // end of measure 1
    let beat16 = s.click(at: 16) // end of ramp
    #expect(abs(beat0.time - 0.0) < 1e-9)
    // Beat 16 at end of ramp = 10.666… seconds
    #expect(abs(beat16.time - (16.0 * 60.0 / 90.0)) < 1e-6)
    // Beat 4 (after 4 beats) — solve quadratic: slope = 6/D where D ≈ 10.666
    // At quarter of the ramp's beats but not quarter of the time (since BPM is rising).
    // Just verify it's between t at constant 60 (4 beats / 60 BPM = 4 sec) and constant 120 (2 sec).
    #expect(beat4.time > 2.0)
    #expect(beat4.time < 4.0)
}

@Test func clickScheduleCountInStaysAtStartBPM() {
    let auto = TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .measures(4))!
    let s = ClickSchedule(
        bpm: BPM(60),
        timeSignature: .fourFour,
        subdivision: .none,
        startTime: 0,
        countInMeasures: 1,
        automation: auto
    )
    // Count-in is 4 clicks at 60 BPM = 1 second per click
    let c0 = s.click(at: 0)
    let c3 = s.click(at: 3)
    #expect(abs(c0.time - 0.0) < 1e-9)
    #expect(abs(c3.time - 3.0) < 1e-9)
    #expect(c0.isCountIn)
    #expect(c3.isCountIn)
    // First song click (index 4) starts immediately after count-in at t=4
    let songStart = s.click(at: 4)
    #expect(!songStart.isCountIn)
    #expect(abs(songStart.time - 4.0) < 1e-9)
}

@Test func clickScheduleWithAutomationAndSubdivisions() {
    // Ramp 60→120 over 4 measures 4/4 with eighth subdivisions.
    // 32 subdivision clicks during the ramp; each at beat position N/2.
    let auto = TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .measures(4))!
    let s = ClickSchedule(
        bpm: BPM(60),
        timeSignature: .fourFour,
        subdivision: .eighth,
        startTime: 0,
        automation: auto
    )
    let totalRampClicks = 32
    // First and last clicks of the ramp
    let first = s.click(at: 0)
    let last = s.click(at: totalRampClicks) // beat 16, end of ramp
    #expect(abs(first.time - 0) < 1e-9)
    #expect(abs(last.time - (16.0 * 60.0 / 90.0)) < 1e-6)
    // A sub-beat click in the middle should be strictly between its neighbors
    for i in 1..<totalRampClicks {
        let prev = s.click(at: i - 1).time
        let here = s.click(at: i).time
        let next = s.click(at: i + 1).time
        #expect(prev < here && here < next, "non-monotonic at i=\(i)")
    }
}

@Test func firstClickIndexAtOrAfterUnderAutomation() {
    // Ramp 60→120 over 4 measures 4/4 (= 16 beats).
    let auto = TempoAutomation(startBPM: BPM(60), endBPM: BPM(120), duration: .measures(4))!
    let s = ClickSchedule(
        bpm: BPM(60),
        timeSignature: .fourFour,
        subdivision: .none,
        startTime: 0,
        automation: auto
    )
    // Time of click 8 → asking for that exact time should return 8.
    let t8 = s.click(at: 8).time
    #expect(s.firstClickIndex(atOrAfter: t8) == 8)
    // A hair before click 8 → still 8.
    #expect(s.firstClickIndex(atOrAfter: t8 - 0.001) == 8)
    // A hair after → next click.
    #expect(s.firstClickIndex(atOrAfter: t8 + 0.001) == 9)
    // Before startTime → 0.
    #expect(s.firstClickIndex(atOrAfter: -1) == 0)
}

// MARK: - Drift verification over a long ramp

@Test func driftAcrossLongRamp() {
    // 60→200 over 5 minutes (300 seconds). Schedule 1000 main beats; check
    // that every beat's `time` matches its expected curve-derived value to
    // sub-microsecond precision (no accumulation).
    let auto = TempoAutomation(startBPM: BPM(60), endBPM: BPM(200), duration: .seconds(300))!
    let s = ClickSchedule(
        bpm: BPM(60),
        timeSignature: .fourFour,
        subdivision: .none,
        startTime: 0,
        automation: auto
    )
    var maxError = 0.0
    for n in 0...1000 {
        let beatPos = Double(n)
        let expectedTime = auto.time(forBeatPosition: beatPos, timeSignature: .fourFour)
        let actualTime = s.click(at: n).time
        let err = abs(actualTime - expectedTime)
        if err > maxError { maxError = err }
    }
    #expect(maxError < 1e-9, "max click-time deviation \(maxError) exceeds floating-point noise")
}
