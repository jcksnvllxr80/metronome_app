import Testing
import Foundation
@testable import MetronomeCore

@Test func defaultsAreReasonable() async {
    let engine = MetronomeEngine(clock: FakeClock())
    let bpm = await engine.bpm
    let ts = await engine.timeSignature
    let sub = await engine.subdivision
    let running = await engine.isRunning
    #expect(bpm == BPM(120))
    #expect(ts == .fourFour)
    #expect(sub == .none)
    #expect(running == false)
}

@Test func stoppedEngineReturnsNoClicks() async {
    let engine = MetronomeEngine(clock: FakeClock())
    let clicks = await engine.upcomingClicks(count: 8)
    #expect(clicks.isEmpty)
}

@Test func firstClickAfterStartIsAccentedDownbeat() async {
    // Regression: real-device QA found that on the very first Play
    // after launch, the first click was missing — perceived accent
    // landed on what felt like beat 4. Root cause: schedule.startTime
    // was clock.now, so the first click's hostTime was in the past
    // by the time the audio path called scheduleBuffer. The lead-in
    // pushes the first click into the future. This test pins both
    // the lead-in shift AND that the first click is still the
    // accented downbeat (so we don't accidentally regress the
    // measure-0/beat-0 invariant while fixing the timing one).
    let clock = FakeClock(start: 100)
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    let first = await engine.upcomingClicks(count: 1).first!
    #expect(first.time > 100, "first click must be strictly after clock.now")
    #expect(first.beatIndex == 0)
    #expect(first.measureIndex == 0)
    #expect(first.subdivisionIndex == 0)
    #expect(first.accent == .accent, "first click must be the accented downbeat")
    #expect(first.isDownbeat)
}

@Test func startAnchorsScheduleAtClockNowPlusLeadIn() async {
    // engine.start applies `startupLeadInSeconds` (120 ms) to the
    // schedule anchor so the first click lands comfortably in the
    // future of the audio path's first scheduleBuffer call. The
    // visual / audio / haptic / MIDI streams all read this same
    // shifted anchor so they stay in sync.
    let clock = FakeClock(start: 100)
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    let clicks = await engine.upcomingClicks(count: 4)
    let leadIn = MetronomeEngine.startupLeadInSeconds
    #expect(clicks.count == 4)
    #expect(clicks[0].time == 100.0 + leadIn)
    #expect(clicks[1].time == 100.5 + leadIn)
    #expect(clicks[2].time == 101.0 + leadIn)
    #expect(clicks[3].time == 101.5 + leadIn)
}

@Test func upcomingClicksAdvanceWithClock() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    let leadIn = MetronomeEngine.startupLeadInSeconds

    let first = await engine.upcomingClicks(count: 1).first!
    #expect(first.time == leadIn)

    // Advance past clicks 0 (at leadIn), 1 (leadIn+0.5), 2 (leadIn+1.0)
    // — next click is index 3 at leadIn + 1.5.
    clock.advance(by: leadIn + 1.25)
    let next = await engine.upcomingClicks(count: 1).first!
    #expect(next.time == leadIn + 1.5)
}

@Test func stopClearsSchedule() async {
    let engine = MetronomeEngine(clock: FakeClock())
    await engine.start()
    let runningBefore = await engine.isRunning
    #expect(runningBefore)

    await engine.stop()
    let runningAfter = await engine.isRunning
    let clicks = await engine.upcomingClicks(count: 4)
    #expect(!runningAfter)
    #expect(clicks.isEmpty)
}

@Test func setBPMWhileStoppedDoesNotStart() async {
    let engine = MetronomeEngine(clock: FakeClock())
    await engine.setBPM(BPM(180))
    let bpm = await engine.bpm
    let running = await engine.isRunning
    #expect(bpm == BPM(180))
    #expect(!running)
}

@Test func setBPMWhileRunningReanchors() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    clock.advance(by: 0.75) // mid-beat

    await engine.setBPM(BPM(60))
    // New schedule should anchor at clock.now = 0.75, with new period = 1.0
    let clicks = await engine.upcomingClicks(count: 3)
    #expect(clicks[0].time == 0.75)
    #expect(clicks[1].time == 1.75)
    #expect(clicks[2].time == 2.75)
}

@Test func setTimeSignatureReanchorsCorrectly() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    clock.advance(by: 0.1)

    await engine.setTimeSignature(.sevenEight)
    let clicks = await engine.upcomingClicks(count: 8)
    // First click of new schedule is a downbeat at t=0.1
    #expect(clicks[0].time == 0.1)
    #expect(clicks[0].isDownbeat)
    // 7/8 wraps after 7 clicks → click 7 is the next downbeat
    #expect(clicks[7].isDownbeat)
}

@Test func setSubdivisionWhileRunning() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(60))
    await engine.start()

    await engine.setSubdivision(.eighth)
    let clicks = await engine.upcomingClicks(count: 4)
    #expect(clicks[0].time == 0.0)
    #expect(clicks[1].time == 0.5)
    #expect(clicks[2].time == 1.0)
    #expect(clicks[3].time == 1.5)
    #expect(clicks[0].subdivisionIndex == 0)
    #expect(clicks[1].subdivisionIndex == 1)
}
