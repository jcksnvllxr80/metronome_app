import Testing
import Foundation
@testable import MetronomeCore

// MARK: - Engine surfaces "ceiling reached" for step-mode automation
// so the view-model polling layer can stop playback when the user's
// target tempo is reached (spec §6.4).
//
// Step automation: startBPM = 60, increment = 20, measuresPerStep = 1,
// ceiling = 100. Steps: 0 → 60, 1 → 80, 2 → 100 (ceiling reached),
// 3+ → 100 (clamped).

private func makeStepEngine(clock: FakeClock) async -> MetronomeEngine {
    let engine = MetronomeEngine(clock: clock, bpm: BPM(60))
    let step = TempoAutomation.Step(
        startBPM: BPM(60),
        increment: 20,
        measuresPerStep: 1,
        ceiling: BPM(100)
    )
    await engine.setAutomation(.step(step))
    await engine.start()
    return engine
}

@Test func ceilingFalseBeforeStart() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(60))
    let step = TempoAutomation.Step(
        startBPM: BPM(60), increment: 20, measuresPerStep: 1, ceiling: BPM(100)
    )
    await engine.setAutomation(.step(step))
    // Not running → ceiling check returns false regardless of clock.
    let hit = await engine.hasReachedAutomationCeiling
    #expect(hit == false)
}

@Test func ceilingFalseEarlyInRamp() async {
    let clock = FakeClock()
    let engine = await makeStepEngine(clock: clock)
    // Step 0 runs from beat 0..3 at 60 BPM = 0..3s (1 measure of 4/4).
    // Clock at 0.5s is mid-step-0 — well below ceiling.
    clock.advance(by: 0.5)
    let hit = await engine.hasReachedAutomationCeiling
    #expect(hit == false)
}

@Test func ceilingTrueAtCeilingStep() async {
    let clock = FakeClock()
    let engine = await makeStepEngine(clock: clock)
    // Step 0 ends after 4 beats @ 60 BPM = 4s (4 beats × 60/60).
    // Step 1 ends after another 4 beats @ 80 BPM = 4 × (60/80) = 3s.
    // So step 2 starts at t = 4 + 3 = 7s. At step 2 BPM = 100 = ceiling.
    clock.advance(by: 7.5)
    let hit = await engine.hasReachedAutomationCeiling
    #expect(hit == true, "Past the ceiling step boundary, ceiling-reached should fire")
}

@Test func ceilingFalseWithoutCeilingConfigured() async {
    // Same step automation but no ceiling — should NEVER report reached.
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(60))
    let step = TempoAutomation.Step(
        startBPM: BPM(60), increment: 20, measuresPerStep: 1, ceiling: nil
    )
    await engine.setAutomation(.step(step))
    await engine.start()
    clock.advance(by: 100) // way past any reasonable step boundary
    let hit = await engine.hasReachedAutomationCeiling
    #expect(hit == false)
}

@Test func ceilingFalseForGradualAutomation() async {
    // Ceiling check is step-only; gradual ramp shouldn't ever fire it.
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(60))
    let g = TempoAutomation.Gradual(
        startBPM: BPM(60), endBPM: BPM(120), duration: .seconds(10)
    )
    await engine.setAutomation(.gradual(g))
    await engine.start()
    clock.advance(by: 20)
    let hit = await engine.hasReachedAutomationCeiling
    #expect(hit == false)
}
