import Foundation

/// Computes BPM from the user tapping a button, per spec §6.1.
///
/// Rules:
/// - Window of the **last 4 taps** (so up to 3 inter-tap intervals).
/// - Reset the window after **2 seconds** of inactivity.
/// - Reject taps closer than 100 ms to the previous tap (anything
///   above 600 BPM is almost certainly a gesture-system double-fire,
///   not an intentional tap). Spec doesn't mandate this floor; it's
///   added in v0.34.2 after real-device QA showed tap tempo over-
///   estimating by 2-4× because of debounce noise polluting the
///   inter-tap intervals.
/// - The BPM estimate is the **median** of the inter-tap intervals,
///   not the arithmetic mean. The spec phrases the rule as a "rolling
///   average" but a single outlier tap (slow first finger, ghost
///   touch, accessibility event injection) wrecks an arithmetic mean
///   and only nudges a median — and a robust mid-value is what users
///   actually want from a "tap to set tempo" affordance. With 4 taps
///   yielding 3 intervals, median = middle value after sorting; this
///   reduces to the same number as mean when the intervals are
///   uniform, so steady tapping behaves identically to the v0.34.1
///   formulation.
/// - Need at least 2 taps before producing an estimate.
///
/// This type is pure data — it does not read the clock. The caller (UI layer)
/// passes the tap time on each invocation, sourced from the same `EngineClock`
/// the engine uses. Same clock = no drift between "what the user tapped" and
/// "what the audio scheduler sees."
public struct TapTempoEstimator: Hashable, Sendable {
    /// Maximum taps retained in the rolling window. 4 taps → up to 3
    /// intervals. Spec §6.1.
    public static let windowSize = 4
    /// Idle time after which the window resets. Spec §6.1.
    public static let inactivityTimeout: TimeInterval = 2.0
    /// Minimum allowable inter-tap interval. Anything tighter is
    /// rejected as a gesture-system double-fire. 100 ms = 600 BPM
    /// ceiling, well above any physically musical tap rate.
    public static let minimumInterval: TimeInterval = 0.1

    public private(set) var taps: [TimeInterval]

    public init() {
        self.taps = []
    }

    /// Register a tap.
    ///
    /// Behavior:
    /// - More than `inactivityTimeout` since the previous tap → the
    ///   window resets first and this tap becomes the start of a fresh
    ///   measurement.
    /// - Less than `minimumInterval` since the previous tap → the tap
    ///   is rejected entirely (window is unchanged). Returns the
    ///   previous estimate.
    /// - Otherwise the tap is appended, the window is trimmed to
    ///   `windowSize`, and the estimate is recomputed.
    ///
    /// Returns the current estimate, or `nil` if we don't have ≥ 2 taps yet.
    @discardableResult
    public mutating func tap(at time: TimeInterval) -> BPM? {
        if let last = taps.last {
            let gap = time - last
            if gap > Self.inactivityTimeout {
                taps.removeAll(keepingCapacity: true)
            } else if gap < Self.minimumInterval {
                // Treat as a double-fire — keep the window as-is.
                return estimate
            }
        }
        taps.append(time)
        if taps.count > Self.windowSize {
            taps.removeFirst(taps.count - Self.windowSize)
        }
        return estimate
    }

    /// Current BPM estimate, or `nil` until we have ≥ 2 taps.
    /// Clamped to the BPM range (20–400) and 0.1 BPM precision by `BPM.init`.
    ///
    /// Median of inter-tap intervals — see the type-level comment for
    /// the rationale. For even-length interval lists the average of
    /// the two middle values is used.
    public var estimate: BPM? {
        guard taps.count >= 2 else { return nil }
        let intervals = zip(taps.dropFirst(), taps).map { $0 - $1 }
        let sorted = intervals.sorted()
        let median: TimeInterval
        if sorted.count.isMultiple(of: 2) {
            let mid = sorted.count / 2
            median = (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }
        guard median > 0 else { return nil }
        return BPM(60.0 / median)
    }

    /// Forget all taps. Use when the user cancels or switches modes.
    public mutating func reset() {
        taps.removeAll(keepingCapacity: true)
    }
}
