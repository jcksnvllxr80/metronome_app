import Foundation

/// Computes BPM from the user tapping a button, per spec §6.1.
///
/// Rules:
/// - Average over the **last 4 taps** (a rolling window of inter-tap intervals).
/// - Reset the window after **2 seconds** of inactivity.
/// - Need at least 2 taps before producing an estimate.
///
/// This type is pure data — it does not read the clock. The caller (UI layer)
/// passes the tap time on each invocation, sourced from the same `EngineClock`
/// the engine uses. Same clock = no drift between "what the user tapped" and
/// "what the audio scheduler sees."
public struct TapTempoEstimator: Hashable, Sendable {
    /// Maximum taps retained in the rolling window. 4 taps → 3 intervals
    /// averaged. Spec §6.1.
    public static let windowSize = 4
    /// Idle time after which the window resets. Spec §6.1.
    public static let inactivityTimeout: TimeInterval = 2.0

    public private(set) var taps: [TimeInterval]

    public init() {
        self.taps = []
    }

    /// Register a tap. If the tap arrives more than `inactivityTimeout`
    /// seconds after the previous one, the window is reset first (the new
    /// tap becomes the start of a fresh measurement).
    /// Returns the current estimate, or `nil` if we don't have ≥ 2 taps yet.
    @discardableResult
    public mutating func tap(at time: TimeInterval) -> BPM? {
        if let last = taps.last, time - last > Self.inactivityTimeout {
            taps.removeAll(keepingCapacity: true)
        }
        taps.append(time)
        if taps.count > Self.windowSize {
            taps.removeFirst(taps.count - Self.windowSize)
        }
        return estimate
    }

    /// Current BPM estimate, or `nil` until we have ≥ 2 taps.
    /// Clamped to the BPM range (20–400) and 0.1 BPM precision by `BPM.init`.
    public var estimate: BPM? {
        guard taps.count >= 2 else { return nil }
        let totalInterval = taps.last! - taps.first!
        let intervalCount = taps.count - 1
        let avgInterval = totalInterval / Double(intervalCount)
        guard avgInterval > 0 else { return nil }
        return BPM(60.0 / avgInterval)
    }

    /// Forget all taps. Use when the user cancels or switches modes.
    public mutating func reset() {
        taps.removeAll(keepingCapacity: true)
    }
}
