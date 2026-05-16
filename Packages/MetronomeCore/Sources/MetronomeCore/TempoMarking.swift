import Foundation

/// Italian tempo marking (Largo, Allegro, etc.) per spec §6.2.
///
/// `bpmRange` is half-open `[lower, upper)`. The classical ranges DO overlap
/// in places (Vivace 168–176 sits inside Presto 168–200) — this is historical
/// and intentional. Use `TempoMarking.primaryMarking(for:)` when you need a
/// single best match for a given BPM (returns the first in `all` that
/// contains the tempo).
public struct TempoMarking: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let bpmRange: Range<Double>

    public init(id: String, name: String, bpmRange: Range<Double>) {
        self.id = id
        self.name = name
        self.bpmRange = bpmRange
    }

    /// Whether this marking covers the given BPM.
    public func contains(_ bpm: BPM) -> Bool {
        bpmRange.contains(bpm.value)
    }

    /// Midpoint of the range — the BPM to load when the user picks this
    /// preset chip. Prestissimo (open upper end) snaps to its lower bound.
    public var defaultBPM: BPM {
        BPM((bpmRange.lowerBound + bpmRange.upperBound) / 2)
    }

    /// The canonical 9-marking list. Order is significant — `primaryMarking`
    /// returns the first match, which means Vivace wins over Presto in the
    /// overlap region (168–176), matching how most reference works present them.
    public static let all: [TempoMarking] = [
        TempoMarking(id: "largo",       name: "Largo",       bpmRange: 40..<60),
        TempoMarking(id: "larghetto",   name: "Larghetto",   bpmRange: 60..<66),
        TempoMarking(id: "adagio",      name: "Adagio",      bpmRange: 66..<76),
        TempoMarking(id: "andante",     name: "Andante",     bpmRange: 76..<108),
        TempoMarking(id: "moderato",    name: "Moderato",    bpmRange: 108..<120),
        TempoMarking(id: "allegro",     name: "Allegro",     bpmRange: 120..<168),
        TempoMarking(id: "vivace",      name: "Vivace",      bpmRange: 168..<176),
        TempoMarking(id: "presto",      name: "Presto",      bpmRange: 168..<200),
        TempoMarking(id: "prestissimo", name: "Prestissimo", bpmRange: 200..<(BPM.maximum + 1)),
    ]

    /// First marking that contains `bpm`, or `nil` if `bpm` is below Largo
    /// (e.g. BPM(20–39) sits below the named range). Useful for highlighting
    /// the active preset chip in the UI.
    public static func primaryMarking(for bpm: BPM) -> TempoMarking? {
        all.first { $0.contains(bpm) }
    }
}
