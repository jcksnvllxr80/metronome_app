import Foundation

/// Optional auto-stop trigger for a `Song`, per spec §7.1.
public enum SongDuration: Hashable, Sendable {
    /// Stop after N complete measures from the song's first downbeat.
    case measures(Int)
    /// Stop after N seconds of playback.
    case seconds(TimeInterval)
}
