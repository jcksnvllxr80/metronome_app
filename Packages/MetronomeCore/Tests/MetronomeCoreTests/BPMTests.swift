import Testing
@testable import MetronomeCore

@Test func bpmClampsBelowMinimum() {
    #expect(BPM(10).value == BPM.minimum)
    #expect(BPM(-50).value == BPM.minimum)
}

@Test func bpmClampsAboveMaximum() {
    #expect(BPM(500).value == BPM.maximum)
    #expect(BPM(1000).value == BPM.maximum)
}

@Test func bpmSnapsDownToPrecision() {
    #expect(BPM(120.04).value == 120.0)
}

@Test func bpmSnapsUpToPrecision() {
    #expect(BPM(120.05).value == 120.1)
    #expect(BPM(120.06).value == 120.1)
}

@Test func bpmAcceptsPreciseValue() {
    #expect(BPM(120.1).value == 120.1)
    #expect(BPM(200.7).value == 200.7)
}

@Test func bpmDisplayIntRoundsHalfUp() {
    #expect(BPM(120.4).displayInt == 120)
    #expect(BPM(120.5).displayInt == 121)
}

@Test func bpmBeatPeriodAt120() {
    #expect(BPM(120).beatPeriod == 0.5)
}

@Test func bpmBeatPeriodAt60() {
    #expect(BPM(60).beatPeriod == 1.0)
}

@Test func bpmIsComparable() {
    #expect(BPM(60) < BPM(120))
    #expect(BPM(200) > BPM(199.9))
}
