import Testing
@testable import MetronomeCore

@Test func validTimeSignatureCreated() throws {
    let ts = try #require(TimeSignature(numerator: 4, denominator: .quarter))
    #expect(ts.numerator == 4)
    #expect(ts.denominator == .quarter)
}

@Test func zeroNumeratorRejected() {
    #expect(TimeSignature(numerator: 0, denominator: .quarter) == nil)
}

@Test func negativeNumeratorRejected() {
    #expect(TimeSignature(numerator: -1, denominator: .quarter) == nil)
}

@Test func tooLargeNumeratorRejected() {
    #expect(TimeSignature(numerator: 33, denominator: .quarter) == nil)
}

@Test func boundaryNumeratorsAccepted() {
    #expect(TimeSignature(numerator: 1, denominator: .whole) != nil)
    #expect(TimeSignature(numerator: 32, denominator: .thirtySecond) != nil)
}

@Test func commonPresetsAreCorrect() {
    #expect(TimeSignature.fourFour.numerator == 4)
    #expect(TimeSignature.fourFour.denominator == .quarter)
    #expect(TimeSignature.sevenEight.numerator == 7)
    #expect(TimeSignature.sevenEight.denominator == .eighth)
    #expect(TimeSignature.twelveEight.numerator == 12)
}

@Test func oddMeterSupported() {
    #expect(TimeSignature(numerator: 11, denominator: .sixteenth) != nil)
    #expect(TimeSignature(numerator: 15, denominator: .eighth) != nil)
}
