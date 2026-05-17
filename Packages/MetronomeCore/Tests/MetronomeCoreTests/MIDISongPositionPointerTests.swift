import Testing
import Foundation
@testable import MetronomeCore

// MARK: - MIDI Song Position Pointer (spec §12.2)
//
// SPP is a 3-byte message (0xF2 + LSB + MSB) reporting "next Start
// should begin at MIDI beat N", where one MIDI beat = one sixteenth
// note. The receiver collects the bytes (with a small state machine
// so real-time status bytes can interleave per MIDI spec), stores the
// 14-bit value, and consumes it on the next 0xFA Start by passing a
// song-time offset to engine.start(positionOffsetSeconds:).
//
// These tests drive `MIDIReceiver.processByte` directly — the
// underlying CoreMIDI helper isn't exercised. That's the only useful
// unit-test surface; real MIDI byte arrival is a system test.

@Test func sppParseBasicValue() async {
    let engine = MetronomeEngine(clock: FakeClock())
    guard let rx = MIDIReceiver() else { return } // simulator may fail; skip if so
    await rx.bind(to: engine)
    await rx.setEnabled(true)

    // SPP value 0x0040 = 64 sixteenths.
    await rx.processByte(0xF2, at: 0)
    await rx.processByte(0x40, at: 0) // LSB
    await rx.processByte(0x00, at: 0) // MSB

    let pending = await rx.pendingMIDIBeats
    #expect(pending == 64)
}

@Test func sppParseMaxValue() async {
    let engine = MetronomeEngine(clock: FakeClock())
    guard let rx = MIDIReceiver() else { return }
    await rx.bind(to: engine)
    await rx.setEnabled(true)

    // 0x7F LSB + 0x7F MSB = 0x3FFF = 16383 (max 14-bit).
    await rx.processByte(0xF2, at: 0)
    await rx.processByte(0x7F, at: 0)
    await rx.processByte(0x7F, at: 0)

    let pending = await rx.pendingMIDIBeats
    #expect(pending == 16383)
}

@Test func sppParseZero() async {
    let engine = MetronomeEngine(clock: FakeClock())
    guard let rx = MIDIReceiver() else { return }
    await rx.bind(to: engine)
    await rx.setEnabled(true)

    await rx.processByte(0xF2, at: 0)
    await rx.processByte(0x00, at: 0)
    await rx.processByte(0x00, at: 0)

    let pending = await rx.pendingMIDIBeats
    #expect(pending == 0, "Explicit SPP 0 stores 0 — distinct from nil (no SPP received)")
}

@Test func sppRealTimeInterleaveDoesNotCorruptCollection() async {
    // MIDI spec says real-time bytes (0xF8..0xFF) can interleave inside
    // any message without breaking it. So 0xF2 0xLSB 0xF8 0xMSB must
    // still decode as a valid SPP — the 0xF8 timing-clock byte should
    // be processed inline without aborting the SPP state machine.
    let engine = MetronomeEngine(clock: FakeClock())
    guard let rx = MIDIReceiver() else { return }
    await rx.bind(to: engine)
    await rx.setEnabled(true)

    await rx.processByte(0xF2, at: 0)
    await rx.processByte(0x10, at: 0) // LSB
    await rx.processByte(0xF8, at: 0) // real-time Clock — should not abort
    await rx.processByte(0x02, at: 0) // MSB

    let pending = await rx.pendingMIDIBeats
    #expect(pending == (UInt16(2) << 7) | UInt16(0x10), "SPP collection survives a Clock byte mid-message")
}

@Test func sppStartConsumesPendingPosition() async {
    // After SPP arrives and Start follows, the engine should start with
    // a positionOffsetSeconds matching the SPP value at the current BPM.
    // At 120 BPM, one sixteenth = 0.125s; SPP 8 = 1.0s.
    // After start, click(0) is at clock.now + leadIn - 1.0 (in the
    // past); the first FUTURE click is at index 8 (8 sixteenths in)
    // when subdivision is .sixteenth.
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.setSubdivision(.sixteenth)
    guard let rx = MIDIReceiver() else { return }
    await rx.bind(to: engine)
    await rx.setEnabled(true)

    // SPP value 8 sixteenths → 1.0 second at 120 BPM.
    await rx.processByte(0xF2, at: 0)
    await rx.processByte(0x08, at: 0) // LSB
    await rx.processByte(0x00, at: 0) // MSB
    // Start (0xFA).
    await rx.processByte(0xFA, at: 0)

    let running = await engine.isRunning
    let pendingAfter = await rx.pendingMIDIBeats
    #expect(running, "Start began playback")
    #expect(pendingAfter == nil, "Pending SPP consumed by Start")

    // Advance to the first future click time and inspect indexing.
    let schedule = await engine.schedule
    #expect(schedule != nil)
    if let schedule {
        // startTime is clock.now (=0) + 0.25 leadIn - 1.0 offset = -0.75
        let expectedStartTime = MetronomeEngine.startupLeadInSeconds - 1.0
        #expect(abs(schedule.startTime - expectedStartTime) < 1e-9,
                "Schedule startTime shifted backward by the SPP offset")
        // At .sixteenth subdivision in 4/4: clicksPerMeasure = 16,
        // partsPerBeat = 4. SPP 8 sixteenths = beat 2 of measure 0
        // (zero-indexed: measure 0, beat 2, sub 0).
        let clickAtPosition = schedule.click(at: 8)
        #expect(clickAtPosition.measureIndex == 0)
        #expect(clickAtPosition.beatIndex == 2)
        #expect(clickAtPosition.subdivisionIndex == 0)
    }
}

@Test func sppStartWithoutPendingPositionStartsAtZero() async {
    // No SPP received → Start should behave identically to a plain
    // engine.start() call (schedule starts at clock.now + leadIn).
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    guard let rx = MIDIReceiver() else { return }
    await rx.bind(to: engine)
    await rx.setEnabled(true)

    await rx.processByte(0xFA, at: 0) // Start with no prior SPP

    let schedule = await engine.schedule
    #expect(schedule != nil)
    if let schedule {
        let expected = MetronomeEngine.startupLeadInSeconds
        #expect(abs(schedule.startTime - expected) < 1e-9,
                "No SPP → schedule starts at clock.now + leadIn (no offset)")
    }
}

@Test func engineStartWithPositionOffsetDisablesCountIn() async {
    // Per the engine API contract: positionOffsetSeconds > 0 implies
    // we're joining mid-song, so the count-in argument is ignored.
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(60))
    await engine.start(countIn: .twoMeasures, positionOffsetSeconds: 2.0)

    let schedule = await engine.schedule
    #expect(schedule != nil)
    #expect(schedule?.countInClicks == 0, "count-in disabled when starting mid-song")
}
