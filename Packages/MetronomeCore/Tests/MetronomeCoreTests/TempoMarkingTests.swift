import Testing
@testable import MetronomeCore

@Test func allMarkingsListedInOrder() {
    let ids = TempoMarking.all.map(\.id)
    #expect(ids == [
        "largo", "larghetto", "adagio", "andante",
        "moderato", "allegro", "vivace", "presto", "prestissimo",
    ])
}

@Test func eachMarkingHasName() {
    for m in TempoMarking.all {
        #expect(!m.name.isEmpty)
        #expect(m.bpmRange.lowerBound < m.bpmRange.upperBound)
    }
}

@Test func largoContainsLowerBound() {
    let largo = TempoMarking.all.first { $0.id == "largo" }!
    #expect(largo.contains(BPM(40)))
    #expect(largo.contains(BPM(59.9)))
    #expect(!largo.contains(BPM(60)))   // upper is exclusive
}

@Test func allegroContains120() {
    let allegro = TempoMarking.all.first { $0.id == "allegro" }!
    #expect(allegro.contains(BPM(120)))
    #expect(allegro.contains(BPM(150)))
    #expect(!allegro.contains(BPM(168)))
}

@Test func prestissimoCapsAtMaxBPM() {
    let p = TempoMarking.all.first { $0.id == "prestissimo" }!
    #expect(p.contains(BPM(200)))
    #expect(p.contains(BPM(400)))    // BPM.maximum
}

@Test func primaryMarkingPicksFirstMatchOnOverlap() {
    // Vivace (168..<176) is listed BEFORE Presto (168..<200), so 170 → Vivace
    #expect(TempoMarking.primaryMarking(for: BPM(170))?.id == "vivace")
}

@Test func primaryMarkingFallsThroughToPresto() {
    // 180 is outside Vivace's range — should land on Presto
    #expect(TempoMarking.primaryMarking(for: BPM(180))?.id == "presto")
}

@Test func primaryMarkingNilBelowLargo() {
    // BPM(20–39) — below Largo's lower bound
    #expect(TempoMarking.primaryMarking(for: BPM(20)) == nil)
    #expect(TempoMarking.primaryMarking(for: BPM(39.9)) == nil)
}

@Test func defaultBPMIsMidpointForBoundedRanges() {
    let andante = TempoMarking.all.first { $0.id == "andante" }!
    // 76..<108 → midpoint 92
    #expect(andante.defaultBPM == BPM(92))
}
