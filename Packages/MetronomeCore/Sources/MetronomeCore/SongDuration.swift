import Foundation

/// Optional auto-stop trigger for a `Song`, per spec §7.1.
public enum SongDuration: Hashable, Sendable {
    /// Stop after N complete measures from the song's first downbeat.
    case measures(Int)
    /// Stop after N seconds of playback.
    case seconds(TimeInterval)
}

extension SongDuration: Codable {
    private enum Kind: String, Codable {
        case measures, seconds
    }
    private enum CodingKeys: String, CodingKey {
        case kind, value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .measures(let n):
            try container.encode(Kind.measures, forKey: .kind)
            try container.encode(n, forKey: .value)
        case .seconds(let s):
            try container.encode(Kind.seconds, forKey: .kind)
            try container.encode(s, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .measures:
            self = .measures(try container.decode(Int.self, forKey: .value))
        case .seconds:
            self = .seconds(try container.decode(TimeInterval.self, forKey: .value))
        }
    }
}
