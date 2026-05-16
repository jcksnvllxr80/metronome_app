import Testing
import Foundation
@testable import MetronomeCore

@Test func fakeClockStartsAtZero() {
    let clock = FakeClock()
    #expect(clock.now == 0)
}

@Test func fakeClockStartsAtGivenInstant() {
    let clock = FakeClock(start: 100)
    #expect(clock.now == 100)
}

@Test func fakeClockAdvances() {
    let clock = FakeClock()
    clock.advance(by: 1.5)
    #expect(clock.now == 1.5)
    clock.advance(by: 0.5)
    #expect(clock.now == 2.0)
}

@Test func systemClockIsMonotonic() {
    let clock = SystemClock()
    let t1 = clock.now
    let t2 = clock.now
    #expect(t2 >= t1)
}

@Test func systemClockMovesForward() async throws {
    let clock = SystemClock()
    let t1 = clock.now
    try await Task.sleep(nanoseconds: 1_000_000) // 1 ms
    let t2 = clock.now
    #expect(t2 > t1)
}
