import Foundation

/// How a `Setlist` transitions from one song to the next, per spec §7.2.
public enum SetlistAdvanceMode: Hashable, Sendable {
    /// Stop after each song; user advances manually.
    case pause
    /// Auto-advance after a silent count-in of N measures at the next song's tempo.
    case countdown(measures: Int)
    /// Auto-advance immediately on the song's last beat.
    case immediate
}

extension SetlistAdvanceMode: Codable {
    private enum Kind: String, Codable {
        case pause, countdown, immediate
    }
    private enum CodingKeys: String, CodingKey {
        case kind, measures
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pause:
            try container.encode(Kind.pause, forKey: .kind)
        case .countdown(let m):
            try container.encode(Kind.countdown, forKey: .kind)
            try container.encode(m, forKey: .measures)
        case .immediate:
            try container.encode(Kind.immediate, forKey: .kind)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .pause: self = .pause
        case .immediate: self = .immediate
        case .countdown:
            self = .countdown(measures: try container.decode(Int.self, forKey: .measures))
        }
    }
}

/// Ordered, mutable collection of `Song`s, per spec §7.2.
///
/// Songs are stored by value (not by reference / by id). When SwiftData
/// lands, this becomes a relationship — until then the value model keeps
/// the type pure and free of persistence concerns.
public struct Setlist: Hashable, Sendable, Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var songs: [Song]
    public var advanceMode: SetlistAdvanceMode

    public init(
        id: UUID = UUID(),
        name: String,
        songs: [Song] = [],
        advanceMode: SetlistAdvanceMode = .pause
    ) {
        self.id = id
        self.name = name
        self.songs = songs
        self.advanceMode = advanceMode
    }

    public var count: Int { songs.count }
    public var isEmpty: Bool { songs.isEmpty }

    public subscript(index: Int) -> Song {
        songs[index]
    }

    /// Song immediately after the one identified by `currentID`, or `nil`
    /// if `currentID` is the last (or not in the setlist).
    public func song(after currentID: Song.ID) -> Song? {
        guard let idx = songs.firstIndex(where: { $0.id == currentID }) else { return nil }
        let next = idx + 1
        guard next < songs.count else { return nil }
        return songs[next]
    }

    /// Song immediately before the one identified by `currentID`, or `nil`
    /// if `currentID` is the first (or not in the setlist).
    public func song(before currentID: Song.ID) -> Song? {
        guard let idx = songs.firstIndex(where: { $0.id == currentID }) else { return nil }
        let prev = idx - 1
        guard prev >= 0 else { return nil }
        return songs[prev]
    }

    public mutating func append(_ song: Song) {
        songs.append(song)
    }

    /// Remove the song with the given `id`. Returns the removed song, or
    /// `nil` if not found.
    @discardableResult
    public mutating func remove(id: Song.ID) -> Song? {
        guard let idx = songs.firstIndex(where: { $0.id == id }) else { return nil }
        return songs.remove(at: idx)
    }

    /// Move the song with the given `id` to `newIndex`. No-ops if the id
    /// isn't found or the index is out of bounds.
    public mutating func move(id: Song.ID, to newIndex: Int) {
        guard let oldIndex = songs.firstIndex(where: { $0.id == id }) else { return }
        guard newIndex >= 0, newIndex < songs.count else { return }
        guard oldIndex != newIndex else { return }
        let song = songs.remove(at: oldIndex)
        songs.insert(song, at: newIndex)
    }
}
