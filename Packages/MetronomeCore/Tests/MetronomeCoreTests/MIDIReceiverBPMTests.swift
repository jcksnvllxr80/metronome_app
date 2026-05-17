import Testing
import Foundation
@testable import MetronomeCore

// MARK: - MIDIReceiver BPM tracking (spec §12.2 slave mode)
//
// The receiver averages inter-tick intervals over a 24-tick window
// (1 beat at 24 PPQ) and pushes the computed BPM to the engine when
// the value moves by ≥ 0.5 BPM. These tests drive processByte
// directly with synthetic clock ticks at known intervals so the
// math is validated independent of CoreMIDI.

@Test func receiverComputesBPMFromTickWindow() async {
    let engine = MetronomeEngine(clock: FakeClock())
    guard let rx = MIDIReceiver() else { return }
    await rx.bind(to: engine)
    await rx.setEnabled(true)
    // Start to reset BPM window.
    await rx.processByte(0xFA, at: 0)

    // 120 BPM = 0.5s/beat = 0.5/24 s/tick ≈ 0.02083 s/tick.
    let tickInterval: TimeInterval = 0.5 / 24.0
    for i in 1...24 {
        await rx.processByte(0xF8, at: TimeInterval(i) * tickInterval)
    }
    let bpm = await engine.bpm
    #expect(abs(bpm.value - 120.0) < 0.5, "Engine BPM tracks 24-tick window at 120 BPM")
}

@Test func receiverTracksTempoChange() async {
    let engine = MetronomeEngine(clock: FakeClock())
    guard let rx = MIDIReceiver() else { return }
    await rx.bind(to: engine)
    await rx.setEnabled(true)
    await rx.processByte(0xFA, at: 0)

    // Establish 60 BPM (1.0s/beat → 1/24 s/tick).
    let slowInterval = 1.0 / 24.0
    var time: TimeInterval = 0
    for _ in 1...24 {
        time += slowInterval
        await rx.processByte(0xF8, at: time)
    }
    let bpmSlow = await engine.bpm
    #expect(abs(bpmSlow.value - 60.0) < 0.5, "BPM converges to 60")

    // Switch to 180 BPM (1/3 s/beat → 1/72 s/tick) and pump enough
    // ticks to fully replace the rolling window.
    let fastInterval = (60.0 / 180.0) / 24.0
    for _ in 1...30 {
        time += fastInterval
        await rx.processByte(0xF8, at: time)
    }
    let bpmFast = await engine.bpm
    #expect(abs(bpmFast.value - 180.0) < 0.5, "BPM follows tempo change to 180")
}

@Test func receiverStopMessageStopsEngine() async {
    let engine = MetronomeEngine(clock: FakeClock())
    guard let rx = MIDIReceiver() else { return }
    await rx.bind(to: engine)
    await rx.setEnabled(true)
    await rx.processByte(0xFA, at: 0)
    let runningBefore = await engine.isRunning
    #expect(runningBefore == true, "Engine starts on 0xFA")

    await rx.processByte(0xFC, at: 1.0)
    let runningAfter = await engine.isRunning
    #expect(runningAfter == false, "Engine stops on 0xFC")
}

@Test func receiverIgnoresMessagesWhenDisabled() async {
    let engine = MetronomeEngine(clock: FakeClock())
    guard let rx = MIDIReceiver() else { return }
    await rx.bind(to: engine)
    await rx.setEnabled(false)
    await rx.processByte(0xFA, at: 0)
    let running = await engine.isRunning
    #expect(running == false, "Disabled receiver ignores Start")
}

@Test func receiverContinueResumesPausedEngine() async {
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock)
    guard let rx = MIDIReceiver() else { return }
    await rx.bind(to: engine)
    await rx.setEnabled(true)
    // Start the engine, pause it, then send Continue.
    await engine.start()
    await engine.pause()
    let pausedBefore = await engine.isPaused
    #expect(pausedBefore == true)

    await rx.processByte(0xFB, at: 5.0)
    let pausedAfter = await engine.isPaused
    let runningAfter = await engine.isRunning
    #expect(pausedAfter == false, "Continue clears paused state")
    #expect(runningAfter == true, "Engine is running after Continue")
}
