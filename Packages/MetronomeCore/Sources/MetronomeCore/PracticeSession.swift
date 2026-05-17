import Foundation

/// A single completed practice run — recorded at engine `stop()`, per
/// spec §11. Immutable value type; one row per session.
///
/// `bpmAtStart` / `bpmAtStop` capture the tempo span without storing a
/// full history of BPM changes. For gradual ramps, that's the ramp's
/// endpoints. For step mode, it's start → wherever-you-stopped. Manual
/// mid-session nudges don't get richer tracking in v1 — the spec asks
/// for "BPM range" and these two endpoints satisfy that.
///
/// `songID` / `songTitle` and `setlistID` / `setlistName` are snapshots,
/// not live references — songs and setlists can be renamed or deleted
/// without breaking historical session rows.
public struct PracticeSession: Hashable, Sendable, Identifiable, Codable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let bpmAtStart: BPM
    public let bpmAtStop: BPM
    /// Minimum BPM observed during the session. For legacy rows
    /// (pre-v0.8.6) this equals `min(bpmAtStart, bpmAtStop)`.
    public let bpmMin: BPM
    /// Maximum BPM observed during the session. Like `bpmMin`, legacy
    /// rows derive from start/stop.
    public let bpmMax: BPM
    public let songID: UUID?
    public let songTitle: String?
    public let setlistID: UUID?
    public let setlistName: String?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        bpmAtStart: BPM,
        bpmAtStop: BPM,
        bpmMin: BPM? = nil,
        bpmMax: BPM? = nil,
        songID: UUID? = nil,
        songTitle: String? = nil,
        setlistID: UUID? = nil,
        setlistName: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        // Defend against startedAt > endedAt — clamp endedAt up. Could
        // happen if a system clock jumps backward mid-session; better to
        // record a zero-duration row than crash.
        self.endedAt = max(startedAt, endedAt)
        self.bpmAtStart = bpmAtStart
        self.bpmAtStop = bpmAtStop
        // When min/max aren't supplied (legacy rows or unaware callers),
        // derive them from start/stop. Both BPMs reachable AT LEAST,
        // so this is a safe lower bound for the actual range.
        let defaultMin = min(bpmAtStart, bpmAtStop)
        let defaultMax = max(bpmAtStart, bpmAtStop)
        self.bpmMin = bpmMin ?? defaultMin
        self.bpmMax = bpmMax ?? defaultMax
        self.songID = songID
        self.songTitle = songTitle
        self.setlistID = setlistID
        self.setlistName = setlistName
    }

    /// Wall-clock duration of the session. Always non-negative (the init
    /// clamps `endedAt` up to `startedAt` if they were inverted).
    public var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}

// MARK: - Aggregations

public extension Sequence where Element == PracticeSession {
    /// Sum of every session's duration, in seconds.
    var totalDuration: TimeInterval {
        reduce(0) { $0 + $1.duration }
    }

    /// Sessions started at or after `date`. Used by the stats screen to
    /// build today / this week / this month windows.
    func started(onOrAfter date: Date) -> [PracticeSession] {
        filter { $0.startedAt >= date }
    }

    /// Group by `songID`, returning aggregated stats per song sorted
    /// by total duration descending. Sessions with no `songID`
    /// aggregate under a sentinel UUID (`.zero`) so freestyle practice
    /// shows up as its own row.
    ///
    /// `bpmMin` / `bpmMax` are the global min / max across all the
    /// session rows in this group (so a song practiced at 60–80 then
    /// later at 100–120 reads 60…120). When a group has no sessions
    /// (shouldn't happen in practice), both are nil.
    func bySong() -> [(id: UUID, title: String, count: Int, totalDuration: TimeInterval, bpmMin: BPM?, bpmMax: BPM?)] {
        let freestyleID = UUID(uuid: UUID_NULL)
        // Tuple-keyed buckets; nested struct doesn't work inside a
        // generic extension method (Swift restriction).
        var buckets: [UUID: (title: String, count: Int, total: TimeInterval, bpmMin: BPM?, bpmMax: BPM?)] = [:]
        for session in self {
            let id = session.songID ?? freestyleID
            let title = session.songTitle ?? "Freestyle"
            var bucket = buckets[id] ?? (title, 0, 0, nil, nil)
            bucket.count += 1
            bucket.total += session.duration
            bucket.bpmMin = bucket.bpmMin.map { Swift.min($0, session.bpmMin) } ?? session.bpmMin
            bucket.bpmMax = bucket.bpmMax.map { Swift.max($0, session.bpmMax) } ?? session.bpmMax
            buckets[id] = bucket
        }
        return buckets
            .map { (id: $0.key, title: $0.value.title, count: $0.value.count,
                    totalDuration: $0.value.total,
                    bpmMin: $0.value.bpmMin, bpmMax: $0.value.bpmMax) }
            .sorted { $0.totalDuration > $1.totalDuration }
    }
}

/// Zero UUID — used as a sentinel for "freestyle" (no associated song)
/// in `bySong()`. Documented + named so it doesn't look like a magic
/// value.
private let UUID_NULL: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

// MARK: - CSV export

public extension Sequence where Element == PracticeSession {
    /// RFC 4180-style CSV with an ISO 8601 timestamp column. Cells that
    /// contain commas, quotes, or newlines get quote-wrapped + escaped.
    /// Suitable for spreadsheet import (Excel, Numbers, Sheets).
    var csv: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var out = "id,started_at,ended_at,duration_seconds,bpm_at_start,bpm_at_stop,bpm_min,bpm_max,song_title,setlist_name\n"
        for session in self {
            let cells: [String] = [
                session.id.uuidString,
                formatter.string(from: session.startedAt),
                formatter.string(from: session.endedAt),
                String(format: "%.3f", session.duration),
                String(session.bpmAtStart.displayInt),
                String(session.bpmAtStop.displayInt),
                String(session.bpmMin.displayInt),
                String(session.bpmMax.displayInt),
                session.songTitle ?? "",
                session.setlistName ?? ""
            ]
            out += cells.map(Self.csvEscape).joined(separator: ",") + "\n"
        }
        return out
    }

    private static func csvEscape(_ raw: String) -> String {
        guard raw.contains(",") || raw.contains("\"") || raw.contains("\n") else {
            return raw
        }
        let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
