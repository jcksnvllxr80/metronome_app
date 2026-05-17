import Foundation

/// User-imported click sound (spec §4.2). The audio file lives in the
/// app sandbox — typically `Documents/UserSounds/<id>.<ext>` — and is
/// loaded into `AVAudioPCMBuffer`s on demand by the audio path. This
/// value type just carries the bookkeeping: a stable ID, a user-visible
/// name, the filename within the sounds directory, and a per-sound
/// volume trim that scales output relative to the built-in click
/// amplitude.
///
/// Identifier format for `EngineSettings.clickSound` / per-song /
/// per-beat overrides: `"user:<UUID>"`. The audio scheduler's sound
/// resolver looks for the `"user:"` prefix and routes through the
/// imported-sound buffer cache; un-prefixed strings keep using the
/// built-in `ClickSound` enum as before.
public struct UserSound: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    /// User-visible label shown in pickers + the import sheet.
    /// Defaults to the source file's basename at import time; user
    /// can rename afterwards.
    public var name: String
    /// File name (e.g. `"abc123.caf"`) inside the app's user-sounds
    /// directory. Storing the bare filename rather than the full URL
    /// makes the value Codable + portable across reinstalls — the app
    /// reconstructs the absolute URL by appending to the Documents
    /// path at runtime.
    public var filename: String
    /// 0.0–1.0 amplitude multiplier applied at buffer pre-render time.
    /// Lets users tame too-loud imports without re-editing the source
    /// file. Clamped at init.
    public var volumeTrim: Double

    public init(
        id: UUID = UUID(),
        name: String,
        filename: String,
        volumeTrim: Double = 1.0
    ) {
        self.id = id
        self.name = name
        self.filename = filename
        self.volumeTrim = max(0, min(1, volumeTrim))
    }

    /// Stable preset key used by the sound resolution chain. Matches
    /// `ClickSound.rawValue` shape but prefixed so callers can detect
    /// user sounds without ambiguity.
    public var soundPresetKey: String { "user:\(id.uuidString)" }

    /// Reverse-lookup helper — extracts the UUID from a preset key
    /// produced by `soundPresetKey`. Returns nil when the key is a
    /// built-in `ClickSound.rawValue` or otherwise unrecognized.
    public static func id(fromKey key: String) -> UUID? {
        let prefix = "user:"
        guard key.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(key.dropFirst(prefix.count)))
    }
}

/// Hard constraints on what counts as a valid imported sound (spec §4.2).
/// Enforced at import time — `AudioScheduler` trusts that anything in
/// its `UserSound` registry already passes these.
public enum UserSoundLimits {
    /// Maximum clip duration in seconds. Anything longer is rejected
    /// during import — long files balloon memory + queue ahead of
    /// the engine clock would behave erratically.
    public static let maxDurationSeconds: TimeInterval = 2.0
    /// Maximum source file size in bytes (1 MiB). Cap exists to keep
    /// the on-disk footprint and decode cost bounded.
    public static let maxFileSizeBytes: Int = 1_048_576
}

/// Reasons a candidate import file may be rejected. Surfaced to the UI
/// so the user can be told exactly which constraint they hit.
public enum UserSoundImportError: Error, Equatable, Sendable {
    /// File extension is not one of WAV / AIFF / CAF (spec §4.2).
    case unsupportedFormat
    /// Source file is larger than `UserSoundLimits.maxFileSizeBytes`.
    case fileTooLarge(bytes: Int)
    /// Source audio is longer than `UserSoundLimits.maxDurationSeconds`.
    case durationTooLong(seconds: TimeInterval)
    /// File couldn't be opened as audio (corrupt / unrecognized).
    case couldNotDecode
    /// IO error during the copy-into-sandbox step.
    case fileSystem(String)
}
