import Foundation

/// User-selectable haptic-feedback policy, per spec §9.
///
/// The actual `CHHapticEngine` lives in `HapticScheduler` (a separate
/// type so this enum stays cross-platform). The scheduler consults
/// this mode at refill time to decide whether each click should
/// trigger a haptic event.
public enum HapticMode: String, Hashable, Sendable, Codable, CaseIterable {
    /// No haptics. Default — many users want audio without buzz.
    case off
    /// Only the first beat of each measure.
    case downbeatOnly
    /// Only clicks whose accent level is `.accent` (the strongest of
    /// the 5-level enum). Useful for following accent patterns by feel.
    case accentsOnly
    /// Every main beat (no subdivision clicks).
    case everyBeat
    /// Every click including subdivisions — most active mode; can feel
    /// overwhelming at high tempos with deep subdivisions.
    case subdivisionsToo

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .downbeatOnly: return "Downbeats only"
        case .accentsOnly: return "Accents only"
        case .everyBeat: return "Every beat"
        case .subdivisionsToo: return "Subdivisions too"
        }
    }

    /// Whether a click at the given accent + position should fire a
    /// haptic event under this mode. Pure decision — no haptic
    /// hardware access. The scheduler asks this for each upcoming
    /// click during refill.
    public func shouldFire(for click: Click) -> Bool {
        switch self {
        case .off:
            return false
        case .downbeatOnly:
            return click.beatIndex == 0 && click.subdivisionIndex == 0
        case .accentsOnly:
            return click.subdivisionIndex == 0 && click.accent == .accent
        case .everyBeat:
            return click.subdivisionIndex == 0 && click.accent != .mute
        case .subdivisionsToo:
            return click.accent != .mute
        }
    }
}
