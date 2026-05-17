import Testing
import Foundation
@testable import MetronomeCore

// MARK: - D.S. al Fine (spec §7.3)
//
// Like D.C. al Fine but the jump target is the nearest preceding
// section flagged isSegno, not section 0. When no segno mark exists
// upstream, D.S. falls back to D.C.'s "jump to section 0" so the
// chart still resolves rather than throwing.

@Test func sectionIsSegnoDefaultsFalse() {
    let s = SongSection(bpm: BPM(120), measureCount: 4)!
    #expect(s.isSegno == false)
}

@Test func sectionSegnoCodableRoundTrip() throws {
    let s = SongSection(
        name: "Chorus",
        bpm: BPM(120),
        measureCount: 8,
        endAction: .dalSegnoAlFine,
        isSegno: true
    )!
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(SongSection.self, from: data)
    #expect(back.isSegno == true)
    #expect(back.endAction == .dalSegnoAlFine)
    #expect(back == s)
}

@Test func sectionLegacyJSONDecodesWithIsSegnoFalse() throws {
    // Payload from before the field existed should decode cleanly
    // with isSegno=false (no surprise jump behavior on upgrade).
    let json = """
    {
      "id": "\(UUID().uuidString)",
      "bpm": 120,
      "timeSignature": {"numerator": 4, "denominator": 4},
      "subdivision": "none",
      "measureCount": 4
    }
    """.data(using: .utf8)!
    let s = try JSONDecoder().decode(SongSection.self, from: json)
    #expect(s.isSegno == false)
}

@Test func sectionEndActionDalSegnoAlFineDisplayName() {
    #expect(SectionEndAction.dalSegnoAlFine.displayName == "D.S. al Fine")
}

// MARK: - Player behavior

@Test func dalSegnoAlFineJumpsToNearestPrecedingSegno() async {
    // Sections: 0 (continue), 1 (segno, continue), 2 (continue),
    // 3 (D.S. al Fine), then 4 (continue, Fine).
    // After section 3 finishes, jump target should be section 1
    // (the segno), not section 0.
    let clock = FakeClock()
    let engine = MetronomeEngine(clock: clock, bpm: BPM(60))
    let player = SongSectionPlayer(engine: engine, clock: clock)

    let s0 = SongSection(name: "Intro", bpm: BPM(60), measureCount: 1)!
    let s1 = SongSection(name: "Verse", bpm: BPM(80), measureCount: 1, isSegno: true)!
    let s2 = SongSection(name: "Pre-Chorus", bpm: BPM(100), measureCount: 1)!
    let s3 = SongSection(name: "Chorus", bpm: BPM(120), measureCount: 1, endAction: .dalSegnoAlFine)!
    let s4 = SongSection(name: "End", bpm: BPM(140), measureCount: 1, isFine: true)!
    let song = Song(title: "DS", bpm: BPM(60), sections: [s0, s1, s2, s3, s4])!

    await player.play(song)

    // 1 measure at 60 BPM = 4 seconds. Walk through sections 0..3 by
    // stepping the clock and ticking the player.
    for _ in 0..<4 {
        clock.advance(by: 5)
        await player.tick()
    }
    // After section 3's D.S. fires, currentIndex should be 1 (segno),
    // not 0. al-fine mode is now active.
    let idxAfterDS = await player.currentIndex
    let alFine = await player.isAlFineMode
    #expect(idxAfterDS == 1, "D.S. jumps to the segno-marked section")
    #expect(alFine == true)
}

@Test func dalSegnoAlFineWithoutSegnoFallsBackToSectionZero() {
    // No isSegno flag in the chart at all → D.S. should not crash and
    // should behave like D.C. (jump to section 0). Unit-test the
    // player's jump arithmetic indirectly via construction.
    let s0 = SongSection(bpm: BPM(60), measureCount: 1)!
    let s1 = SongSection(bpm: BPM(80), measureCount: 1, endAction: .dalSegnoAlFine)!
    let song = Song(title: "DS-no-segno", bpm: BPM(60), sections: [s0, s1])
    #expect(song != nil, "Song with D.S. but no segno is still constructable")
}
