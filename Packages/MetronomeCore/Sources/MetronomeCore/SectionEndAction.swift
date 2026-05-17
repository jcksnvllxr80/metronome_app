import Foundation

/// What `SongSectionPlayer` should do after a `SongSection`'s
/// `measureCount * repeatCount` measures finish, per spec §7.3
/// "Optional repeat markers / DC al fine logic."
///
/// `.continue` is the default — advance to the next section in order.
/// `.stop` is the explicit "end of song here." `.daCapoAlFine` jumps
/// back to section 0 and plays in al-fine mode: as soon as a section
/// marked `isFine` finishes, playback ends. `.dalSegnoAlFine` is the
/// same idea but jumps to the nearest preceding section flagged
/// `isSegno` (or section 0 as a fallback) — common in chart notation
/// when the head and the form's "real" repeat target differ.
///
/// `.daCapoAlCoda` and `.dalSegnoAlCoda` are the two-pass coda jumps:
/// on the FIRST encounter the player jumps to section 0 / segno and
/// enters al-coda mode; on the SECOND encounter the same section's
/// natural boundary instead jumps forward to the next section
/// flagged `isCoda`. This is the typical "D.S. al Coda — to coda,
/// then jump" notation in chart music.
public enum SectionEndAction: String, Hashable, Sendable, Codable, CaseIterable {
    case `continue`
    case stop
    case daCapoAlFine
    case dalSegnoAlFine
    case daCapoAlCoda
    case dalSegnoAlCoda

    public var displayName: String {
        switch self {
        case .continue: return "Continue"
        case .stop: return "Stop"
        case .daCapoAlFine: return "D.C. al Fine"
        case .dalSegnoAlFine: return "D.S. al Fine"
        case .daCapoAlCoda: return "D.C. al Coda"
        case .dalSegnoAlCoda: return "D.S. al Coda"
        }
    }
}
