import Foundation

/// One scheduled audio event from the engine.
///
/// The engine pre-computes a sequence of these so the audio scheduler can
/// keep 4–8 beats queued ahead of `clock.now` per spec §1.2.
public struct Click: Hashable, Sendable {
    /// 0-based beat-in-measure. Wraps at `timeSignature.numerator`.
    public let beatIndex: Int
    /// 0-based subdivision-within-beat. `0` is the main beat; `1...(partsPerBeat-1)` are interstitial clicks.
    public let subdivisionIndex: Int
    /// 0-based measure counter since the engine started.
    public let measureIndex: Int
    /// When this click fires, in `EngineClock` time.
    public let time: TimeInterval
    /// How this click should be played.
    public let accent: AccentLevel

    /// First click of the first beat of a measure.
    public var isDownbeat: Bool {
        beatIndex == 0 && subdivisionIndex == 0
    }

    /// First click of any beat (not a subdivision).
    public var isMainBeat: Bool {
        subdivisionIndex == 0
    }
}
