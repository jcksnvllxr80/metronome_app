import Testing
import Foundation
@testable import MetronomeCore

// MARK: - EngineSettings.autoResumeAfterInterruption

@Test func autoResumeDefaultsToOff() {
    let s = EngineSettings()
    #expect(s.autoResumeAfterInterruption == false)
}

@Test func autoResumeCanBeEnabled() {
    let s = EngineSettings(autoResumeAfterInterruption: true)
    #expect(s.autoResumeAfterInterruption == true)
}

// MARK: - Pause / Resume

@Test func pauseWhenStoppedIsNoop() async {
    let engine = MetronomeEngine(clock: FakeClock())
    await engine.pause()
    let running = await engine.isRunning
    let paused = await engine.isPaused
    #expect(running == false)
    #expect(paused == false)
}

@Test func pauseFromRunningSetsPausedFlag() async {
    let engine = MetronomeEngine(clock: FakeClock())
    await engine.start()
    await engine.pause()
    let running = await engine.isRunning
    let paused = await engine.isPaused
    let schedule = await engine.schedule
    #expect(running == false)
    #expect(paused == true)
    #expect(schedule != nil, "schedule must be preserved across pause")
}

@Test func resumeWhenNotPausedIsNoop() async {
    let engine = MetronomeEngine(clock: FakeClock())
    await engine.resume()
    let running = await engine.isRunning
    #expect(running == false)
}

@Test func resumeFromPausedReanchorsAtClockNow() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    clock.advance(by: 5.0)
    await engine.pause()
    clock.advance(by: 10.0) // sat paused for 10 sec
    await engine.resume()

    // After resume, the first upcoming click is at clock.now (15.0),
    // not at the original startTime + N beats.
    let next = await engine.upcomingClicks(count: 1).first!
    #expect(next.time == 15.0)
    #expect(next.isDownbeat)
}

@Test func stopAfterPauseClearsPausedFlag() async {
    let engine = MetronomeEngine(clock: FakeClock())
    await engine.start()
    await engine.pause()
    await engine.stop()
    let running = await engine.isRunning
    let paused = await engine.isPaused
    let schedule = await engine.schedule
    #expect(running == false)
    #expect(paused == false)
    #expect(schedule == nil)
}

@Test func startAfterPauseStartsFresh() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()
    clock.advance(by: 2.0)
    await engine.pause()
    clock.advance(by: 1.0)
    await engine.start()  // user pressed Play again — fresh start
    let paused = await engine.isPaused
    let running = await engine.isRunning
    #expect(paused == false)
    #expect(running == true)
    let next = await engine.upcomingClicks(count: 1).first!
    // start() always re-anchors at clock.now (3.0), not where pause was (2.0)
    #expect(next.time == 3.0)
}
