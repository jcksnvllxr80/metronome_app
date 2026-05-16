import Foundation
import Darwin
import AVFoundation

/// Monotonic time source for the metronome engine. Production code uses
/// `SystemClock`; tests inject `FakeClock` to verify scheduled-event accuracy
/// without producing audio.
///
/// Named `EngineClock` (not `Clock`) to avoid shadowing the Swift standard
/// library's `Clock` protocol, whose `Instant`/`Duration` shape doesn't fit
/// the engine's `TimeInterval`-based scheduling needs.
public protocol EngineClock: Sendable {
    /// Seconds since an arbitrary fixed reference. Monotonic — never decreases.
    var now: TimeInterval { get }
}

/// Production clock backed by `mach_absolute_time`. Shares its time base with
/// `AVAudioTime.hostTime`, which the audio engine needs for sample-accurate
/// scheduling — using `ContinuousClock` or `Date` here would introduce drift
/// against the audio output's host time.
public struct SystemClock: EngineClock {
    fileprivate static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init() {}

    public var now: TimeInterval {
        let raw = mach_absolute_time()
        let nanos = raw &* UInt64(Self.timebase.numer) / UInt64(Self.timebase.denom)
        return TimeInterval(nanos) / 1_000_000_000
    }

    /// Returns an `AVAudioTime` whose `hostTime` corresponds to the given
    /// `EngineClock` time. Used by the audio scheduler when calling
    /// `AVAudioPlayerNode.scheduleBuffer(at:)` — `hostTime` is a
    /// `mach_absolute_time` tick value in the same time base as `now`,
    /// so passing through this bridge means audio output and `EngineClock`
    /// readings share a single reference and don't drift relative to each
    /// other. Inverse of the `now` getter's seconds-from-ticks conversion.
    public func audioTime(forEngineTime engineTime: TimeInterval) -> AVAudioTime {
        let nanos = engineTime * 1_000_000_000
        let timebase = Self.timebase
        let ticks = UInt64(nanos) &* UInt64(timebase.denom) / UInt64(timebase.numer)
        return AVAudioTime(hostTime: ticks)
    }
}

/// Deterministic clock for tests. Time only moves when `advance(by:)` is called.
public final class FakeClock: EngineClock, @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval

    public init(start: TimeInterval = 0) {
        self.seconds = start
    }

    public var now: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return seconds
    }

    public func advance(by delta: TimeInterval) {
        precondition(delta >= 0, "FakeClock cannot go backwards")
        lock.lock(); defer { lock.unlock() }
        seconds += delta
    }
}
