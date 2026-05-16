import Testing
import Foundation
@testable import MetronomeCore

@Test func clicksAfterReturnsEmptyWhenStopped() async {
    let engine = MetronomeEngine(clock: FakeClock())
    let clicks = await engine.clicks(after: 0, count: 4)
    #expect(clicks.isEmpty)
}

@Test func clicksAfterReturnsNextClicksFromStart() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    // First click is at t=0; passing -1 should return clicks from index 0
    let clicks = await engine.clicks(after: -1, count: 4)
    #expect(clicks.count == 4)
    #expect(clicks[0].time == 0.0)
    #expect(clicks[1].time == 0.5)
}

@Test func clicksAfterSkipsAlreadyReturnedClicks() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    // First batch — schedule clicks 0..3 (times 0.0, 0.5, 1.0, 1.5)
    let first = await engine.clicks(after: -1, count: 4)
    // Second batch — only clicks AFTER the last returned time
    let second = await engine.clicks(after: first.last!.time, count: 4)
    // Should be clicks 4..7 (times 2.0, 2.5, 3.0, 3.5)
    #expect(second[0].time == 2.0)
    #expect(second[1].time == 2.5)
}

@Test func clicksAfterHandlesExactBoundary() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    // Asking for clicks after t=0.5 (which IS click index 1) should
    // return clicks starting at index 2 (t=1.0), not re-return index 1.
    let clicks = await engine.clicks(after: 0.5, count: 2)
    #expect(clicks[0].time == 1.0)
    #expect(clicks[1].time == 1.5)
}

@Test func clicksAfterRespectsReanchor() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    _ = await engine.clicks(after: -1, count: 4)

    // Advance time + change BPM → reanchor at clock.now
    clock.advance(by: 0.3)
    await engine.setBPM(BPM(60))

    // After reanchor, `clicks(after:)` should produce the NEW schedule's
    // clicks, starting at the new startTime (0.3).
    let clicks = await engine.clicks(after: -1, count: 2)
    #expect(clicks[0].time == 0.3)
    #expect(clicks[1].time == 1.3) // 60 BPM = 1.0 sec period
}
