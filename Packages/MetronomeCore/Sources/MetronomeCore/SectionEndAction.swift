import Foundation

/// What `SongSectionPlayer` should do after a `SongSection`'s
/// `measureCount * repeatCount` measures finish, per spec §7.3
/// "Optional repeat markers / DC al fine logic."
///
/// `.continue` is the default — advance to the next section in order.
/// `.stop` is the explicit "end of song here." `.daCapoAlFine` jumps
/// back to section 0 and plays in al-fine mode: as soon as a section
/// marked `isFine` finishes, playback ends.
///
/// Segno (jump-source-other-than-section-0) + coda (mid-pass jump
/// destination) are out of scope for v1. Adding them later is a
/// matter of new enum cases + companion flag fields on `SongSection`.
public enum SectionEndAction: String, Hashable, Sendable, Codable, CaseIterable {
    case `continue`
    case stop
    case daCapoAlFine

    public var displayName: String {
        switch self {
        case .continue: return "Continue"
        case .stop: return "Stop"
        case .daCapoAlFine: return "D.C. al Fine"
        }
    }
}
