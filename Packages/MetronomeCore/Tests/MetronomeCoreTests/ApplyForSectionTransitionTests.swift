import Testing
import Foundation
@testable import MetronomeCore

// MARK: - Engine-level verification that section transitions land
// the correct BPM / time signature / subdivision in the engine
// schedule. If these tests fail, the bug is in the engine's apply
// chain; if they pass, the bug is downstream in the audio scheduler.

@Test func applyForSectionTransitionUpdatesBPM() async {
    // Build a song with 3 sections at clearly different BPMs.
    let s1 = SongSection(name: "A", bpm: BPM(60),  measureCount: 4)!
    let s2 = SongSection(name: "B", bpm: BPM(120), measureCount: 4)!
    let s3 = SongSection(name: "C", bpm: BPM(180), measureCount: 4)!
    let parent = Song(
        title: "ThreeTempos",
        bpm: BPM(60),
        sections: [s1, s2, s3]
    )!
    let clock = FakeClock()
    // Don't attach any scheduler — applyForSectionTransition's detach
    // step is fine with nil. We're checking engine.schedule, not audio.
    let engine = MetronomeEngine(clock: clock, bpm: BPM(60))
    await engine.start()

    // Apply section 1.
    let m1 = materialize(s1, parent: parent)
    await engine.applyForSectionTransition(m1, sectionMeasureCount: s1.measureCount)
    let bpmAfter1 = await engine.bpm
    let scheduleBpm1 = await engine.schedule?.bpm
    #expect(bpmAfter1 == BPM(60))
    #expect(scheduleBpm1 == BPM(60))

    // Advance clock; apply section 2 with new BPM.
    clock.advance(by: 5)
    let m2 = materialize(s2, parent: parent)
    await engine.applyForSectionTransition(m2, sectionMeasureCount: s2.measureCount)
    let bpmAfter2 = await engine.bpm
    let scheduleBpm2 = await engine.schedule?.bpm
    #expect(bpmAfter2 == BPM(120), "engine.bpm should advance to section 2's BPM")
    #expect(scheduleBpm2 == BPM(120), "engine.schedule.bpm should advance to section 2's BPM")

    // Section 3.
    clock.advance(by: 5)
    let m3 = materialize(s3, parent: parent)
    await engine.applyForSectionTransition(m3, sectionMeasureCount: s3.measureCount)
    let bpmAfter3 = await engine.bpm
    let scheduleBpm3 = await engine.schedule?.bpm
    #expect(bpmAfter3 == BPM(180))
    #expect(scheduleBpm3 == BPM(180))
}

@Test func applyForSectionTransitionUpdatesTimeSignatureAndSubdivision() async {
    let s1 = SongSection(name: "4/4 quarter",
                         bpm: BPM(120),
                         timeSignature: .fourFour,
                         subdivision: .none,
                         measureCount: 4)!
    let s2 = SongSection(name: "6/8 eighth",
                         bpm: BPM(120),
                         timeSignature: TimeSignature(numerator: 6, denominator: .eighth)!,
                         subdivision: .eighth,
                         measureCount: 4)!
    let parent = Song(title: "MeterChange", bpm: BPM(120), sections: [s1, s2])!
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(120))
    await engine.start()

    let m1 = materialize(s1, parent: parent)
    await engine.applyForSectionTransition(m1, sectionMeasureCount: s1.measureCount)
    let ts1 = await engine.timeSignature
    let sub1 = await engine.subdivision
    #expect(ts1 == .fourFour)
    #expect(sub1 == .none)

    clock.advance(by: 5)
    let m2 = materialize(s2, parent: parent)
    await engine.applyForSectionTransition(m2, sectionMeasureCount: s2.measureCount)
    let ts2 = await engine.timeSignature
    let sub2 = await engine.subdivision
    #expect(ts2.numerator == 6)
    #expect(ts2.denominator == .eighth)
    #expect(sub2 == .eighth)
}

@Test func applyForSectionTransitionReanchorsScheduleStartTime() async {
    let s1 = SongSection(bpm: BPM(60), measureCount: 4)!
    let s2 = SongSection(bpm: BPM(120), measureCount: 4)!
    let parent = Song(title: "x", bpm: BPM(60), sections: [s1, s2])!
    let clock = FakeClock(start: 100)
    let engine = MetronomeEngine(clock: clock, bpm: BPM(60))
    await engine.start()

    let m1 = materialize(s1, parent: parent)
    await engine.applyForSectionTransition(m1, sectionMeasureCount: s1.measureCount)
    let start1 = await engine.schedule?.startTime ?? -1
    // After start at clock 100, applyForSectionTransition re-anchors
    // at clock.now (still 100, since no advance) + reanchor lead-in.
    #expect(abs(start1 - (100 + MetronomeEngine.reanchorLeadInSeconds)) < 1e-9)

    clock.advance(by: 16) // 4 measures at 60 BPM = 16 seconds
    let m2 = materialize(s2, parent: parent)
    await engine.applyForSectionTransition(m2, sectionMeasureCount: s2.measureCount)
    let start2 = await engine.schedule?.startTime ?? -1
    // Second section anchors at clock.now (116) + reanchor lead-in.
    #expect(abs(start2 - (116 + MetronomeEngine.reanchorLeadInSeconds)) < 1e-9)
}

// MARK: - Helper that mirrors SongSectionPlayer.materialize so tests
// don't have to import the private static method.

private func materialize(_ section: SongSection, parent: Song) -> Song {
    return Song(
        id: parent.id,
        title: parent.title,
        bpm: section.bpm,
        timeSignature: section.timeSignature,
        subdivision: section.subdivision,
        accentPattern: section.accentPattern,
        soundPreset: section.soundPreset ?? parent.soundPreset,
        notes: parent.notes,
        duration: nil,
        automation: nil,
        sections: nil
    ) ?? parent
}
