import Testing
import Foundation
import Darwin
import AVFoundation
@testable import MetronomeCore

/// Confirms the seconds→hostTime conversion is the inverse of the
/// hostTime→seconds conversion `SystemClock.now` performs. Drift here
/// would mean every scheduled click lands at the wrong sample, which
/// breaks the spec's < 1 ms/minute timing budget.

@Test func audioTimeRoundTripAtZero() {
    let clock = SystemClock()
    let audioTime = clock.audioTime(forEngineTime: 0)
    #expect(audioTime.hostTime == 0)
}

@Test func audioTimeRoundTripAtOneSecond() {
    let clock = SystemClock()
    let inputSeconds: TimeInterval = 1.0
    let audioTime = clock.audioTime(forEngineTime: inputSeconds)

    // Convert hostTime back to seconds the same way SystemClock.now does.
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let nanos = audioTime.hostTime &* UInt64(info.numer) / UInt64(info.denom)
    let backToSeconds = TimeInterval(nanos) / 1_000_000_000

    let drift = abs(backToSeconds - inputSeconds)
    #expect(drift < 1e-6, "Round-trip drift must stay under 1 µs")
}

@Test func audioTimeRoundTripAtFiveMinutes() {
    let clock = SystemClock()
    let inputSeconds: TimeInterval = 300.0
    let audioTime = clock.audioTime(forEngineTime: inputSeconds)

    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let nanos = audioTime.hostTime &* UInt64(info.numer) / UInt64(info.denom)
    let backToSeconds = TimeInterval(nanos) / 1_000_000_000

    let drift = abs(backToSeconds - inputSeconds)
    #expect(drift < 1e-6, "Round-trip drift must stay under 1 µs even at 5 min")
}

@Test func audioTimeMonotonicallyAdvances() {
    let clock = SystemClock()
    let earlier = clock.audioTime(forEngineTime: 10.0)
    let later   = clock.audioTime(forEngineTime: 11.0)
    #expect(later.hostTime > earlier.hostTime)
}
