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
/// Coda (mid-pass jump destination) + D.S. al Coda are still out of
/// scope for v1; adding them later just means another case + a
/// companion `isCoda` flag on SongSection.
public enum SectionEndAction: String, Hashable, Sendable, Codable, CaseIterable {
    case `continue`
    case stop
    case daCapoAlFine
    case dalSegnoAlFine

    public var displayName: String {
        switch self {
        case .continue: return "Continue"
        case .stop: return "Stop"
        case .daCapoAlFine: return "D.C. al Fine"
        case .dalSegnoAlFine: return "D.S. al Fine"
        }
    }
}
