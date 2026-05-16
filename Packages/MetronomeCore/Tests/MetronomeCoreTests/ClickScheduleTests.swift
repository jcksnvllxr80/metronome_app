import Testing
import Foundation
@testable import MetronomeCore

// MARK: - clickPeriod / clicksPerMeasure

@Test func clickPeriodAt120NoSubdivision() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    #expect(s.clickPeriod == 0.5)
    #expect(s.clicksPerMeasure == 4)
}

@Test func clickPeriodAt120Triplets() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .triplet, startTime: 0)
    #expect(s.clickPeriod == 0.5 / 3)
    #expect(s.clicksPerMeasure == 12)
}

@Test func clicksPerMeasureForOddMeter() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .sevenEight, subdivision: .none, startTime: 0)
    #expect(s.clicksPerMeasure == 7)
}

// MARK: - click(at:) — measure/beat/sub computation

@Test func firstClickIsDownbeat() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    let c = s.click(at: 0)
    #expect(c.beatIndex == 0)
    #expect(c.subdivisionIndex == 0)
    #expect(c.measureIndex == 0)
    #expect(c.time == 0)
    #expect(c.accent == .accent)
    #expect(c.isDownbeat)
}

@Test func secondClickIsBeatTwo() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    let c = s.click(at: 1)
    #expect(c.beatIndex == 1)
    #expect(c.measureIndex == 0)
    #expect(c.accent == .normal)
    #expect(!c.isDownbeat)
    #expect(c.isMainBeat)
}

@Test func wrapsToNextMeasure() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    let c = s.click(at: 4)
    #expect(c.beatIndex == 0)
    #expect(c.measureIndex == 1)
    #expect(c.accent == .accent)
}

@Test func subdivisionClicksAreSoft() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .eighth, startTime: 0)
    let downbeat = s.click(at: 0)
    let upbeat = s.click(at: 1)
    #expect(downbeat.beatIndex == 0)
    #expect(downbeat.subdivisionIndex == 0)
    #expect(downbeat.accent == .accent)
    #expect(upbeat.beatIndex == 0)
    #expect(upbeat.subdivisionIndex == 1)
    #expect(upbeat.accent == .soft)
    #expect(!upbeat.isMainBeat)
}

@Test func tripletPositionsCorrect() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .triplet, startTime: 0)
    // 12 clicks per measure (4 beats × 3 triplets)
    for i in 0..<12 {
        let c = s.click(at: i)
        #expect(c.measureIndex == 0)
        #expect(c.beatIndex == i / 3)
        #expect(c.subdivisionIndex == i % 3)
    }
    // Click 12 should wrap to next measure, beat 0, sub 0
    let wrap = s.click(at: 12)
    #expect(wrap.measureIndex == 1)
    #expect(wrap.beatIndex == 0)
    #expect(wrap.subdivisionIndex == 0)
}

@Test func oddMeterDownbeatWrap() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .sevenEight, subdivision: .none, startTime: 0)
    let click7 = s.click(at: 7)
    #expect(click7.measureIndex == 1)
    #expect(click7.beatIndex == 0)
    #expect(click7.accent == .accent)
}

// MARK: - drift budget

@Test func zeroDriftOverOneMinute() {
    // 120 BPM, no subdivision → exactly 120 main beats per 60 seconds.
    // The 120th beat (index 120) must fire at t = 60.0 exactly.
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    let c120 = s.click(at: 120)
    let drift = abs(c120.time - 60.0)
    #expect(drift < 0.001, "Drift over 1 minute must stay under 1 ms (spec §1.1)")
}

@Test func zeroDriftAt400BPMOverOneMinute() {
    // At the upper tempo bound, 400 beats per minute. Index 400 → t = 60.0.
    let s = ClickSchedule(bpm: BPM(400), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    let c400 = s.click(at: 400)
    let drift = abs(c400.time - 60.0)
    #expect(drift < 0.001, "Drift over 1 minute at 400 BPM must stay under 1 ms")
}

@Test func zeroDriftWithStartOffset() {
    // Drift budget must hold regardless of where startTime is anchored
    // (e.g. when the engine starts mid-session).
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 1_234_567.89)
    let c120 = s.click(at: 120)
    let drift = abs(c120.time - (1_234_567.89 + 60.0))
    #expect(drift < 0.001)
}

// MARK: - firstClickIndex / clicks(from:count:)

@Test func firstClickIndexBeforeStartReturnsZero() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 100)
    #expect(s.firstClickIndex(atOrAfter: 50) == 0)
    #expect(s.firstClickIndex(atOrAfter: 100) == 0)
}

@Test func firstClickIndexExactlyAtClick() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    // clickPeriod = 0.5, so click 2 is at t = 1.0
    #expect(s.firstClickIndex(atOrAfter: 1.0) == 2)
}

@Test func firstClickIndexMidBeatRoundsUp() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    // 1.25 is between click 2 (t=1.0) and click 3 (t=1.5) → next is 3
    #expect(s.firstClickIndex(atOrAfter: 1.25) == 3)
}

@Test func clicksFromReturnsContiguousSequence() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    let clicks = s.clicks(from: 1.25, count: 3)
    #expect(clicks.count == 3)
    #expect(clicks[0].time == 1.5)
    #expect(clicks[1].time == 2.0)
    #expect(clicks[2].time == 2.5)
}

@Test func clicksFromZeroCount() {
    let s = ClickSchedule(bpm: BPM(120), timeSignature: .fourFour, subdivision: .none, startTime: 0)
    #expect(s.clicks(from: 0, count: 0).isEmpty)
}
