import Foundation
import AVFoundation

/// Sendable wrapper around an `AVAudioPCMBuffer`. The buffer is only
/// ever read after `UserSoundRegistry` finishes writing it (callers
/// of `setSounds` await its completion), and `AVAudioPlayerNode`'s
/// `scheduleBuffer` is thread-safe — so the unchecked Sendable is
/// safe in this narrow case.
public struct UserSoundBufferRef: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer
    public init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}

/// Per-accent buffer cache for one user-imported sound. Built once at
/// import time (or on first reference after app launch) and held in
/// memory by `UserSoundRegistry`. Pre-rendering five accent-level
/// variants here means the audio refill loop pays no signal-processing
/// cost per click — just a dictionary lookup.
private struct UserSoundBufferSet {
    /// Source audio resampled to the scheduler's mix format, with the
    /// `UserSound.volumeTrim` already baked in. One copy per accent
    /// level so the audio path can pick the right amplitude without
    /// touching the playback node's volume (which is owned by the
    /// primary mix).
    var byAccent: [AccentLevel: UserSoundBufferRef]
}

/// In-memory registry mapping `UserSound.id` to pre-rendered buffers
/// and the source `UserSound` metadata. Owned by the audio scheduler;
/// callers update it as user sounds are added / removed / re-trimmed
/// in the UI. Buffer loading uses `AVAudioFile` so the source format
/// is converted to the scheduler's mix format at load time — the audio
/// refill loop then just plays the cached buffer.
///
/// File IO + sandbox path resolution lives in the app target's store
/// layer; this actor just takes URLs as input. Keeps `MetronomeCore`
/// free of any opinion about *where* sounds live on disk.
public actor UserSoundRegistry {
    /// Currently loaded sounds, keyed by ID. Updated whenever the
    /// store layer pushes a fresh snapshot via `setSounds(_:format:)`.
    public private(set) var sounds: [UUID: UserSound] = [:]
    /// Buffers per sound × accent. Stored separately from `sounds`
    /// because the source dictionary is what callers see in pickers
    /// and the audio path needs only the buffers.
    private var bufferSets: [UUID: UserSoundBufferSet] = [:]

    public init() {}

    /// Replace the registry's contents with a new snapshot. Sounds that
    /// disappeared have their buffers freed; new sounds are pre-rendered
    /// using `urlFor(_:)` to resolve their on-disk location. Buffers for
    /// sounds whose `volumeTrim` changed are also re-rendered so the
    /// new trim applies immediately.
    public func setSounds(
        _ next: [UserSound],
        format: AVAudioFormat,
        urlFor: (UserSound) -> URL
    ) async {
        let nextByID: [UUID: UserSound] = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })

        // Drop buffers for removed or volume-changed entries.
        for (id, existing) in sounds {
            guard let new = nextByID[id] else {
                bufferSets[id] = nil
                continue
            }
            if abs(existing.volumeTrim - new.volumeTrim) > 1e-6 {
                bufferSets[id] = nil
            }
        }

        // Load buffers for new or invalidated entries.
        for sound in next where bufferSets[sound.id] == nil {
            let url = urlFor(sound)
            if let set = Self.loadBufferSet(from: url, trim: sound.volumeTrim, format: format) {
                bufferSets[sound.id] = set
            }
        }

        sounds = nextByID
    }

    /// Buffer for a given (sound, accent) pair, or nil when the sound
    /// is missing, failed to load, or the accent is mute (caller is
    /// expected to filter mute clicks before reaching the audio path).
    /// Returns a `UserSoundBufferRef` so the buffer can cross actor
    /// boundaries — `AVAudioPCMBuffer` itself isn't Sendable.
    public func buffer(for id: UUID, accent: AccentLevel) -> UserSoundBufferRef? {
        bufferSets[id]?.byAccent[accent]
    }

    // MARK: - Loading

    /// Load an audio file and pre-render five per-accent volume
    /// variants. Returns nil when the file can't be opened or the
    /// frame count doesn't match the constraints — the registry
    /// trusts that import-time validation already covered duration +
    /// file-size limits, but a defensive file-open check is cheap.
    private static func loadBufferSet(
        from url: URL,
        trim: Double,
        format: AVAudioFormat
    ) -> UserSoundBufferSet? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { return nil }
        // Read at the source format, then convert to the mixer format
        // when caching. Converting at load time means the refill loop
        // never pays format-conversion cost per click.
        let srcFormat = file.processingFormat
        guard let srcBuffer = AVAudioPCMBuffer(
            pcmFormat: srcFormat, frameCapacity: frameCount
        ) else { return nil }
        do {
            try file.read(into: srcBuffer)
        } catch {
            return nil
        }

        // Five accent-volume variants. AccentLevel.mute is omitted —
        // mute clicks are filtered before reaching the audio path.
        let multipliers: [AccentLevel: Float] = [
            .soft:   0.30,
            .normal: 0.60,
            .loud:   0.85,
            .accent: 1.00,
        ]
        var byAccent: [AccentLevel: UserSoundBufferRef] = [:]
        for (level, mul) in multipliers {
            guard let scaled = Self.scaledCopy(
                of: srcBuffer,
                amplitude: mul * Float(trim),
                targetFormat: format
            ) else { continue }
            byAccent[level] = UserSoundBufferRef(scaled)
        }
        return UserSoundBufferSet(byAccent: byAccent)
    }

    /// Build a new buffer in `targetFormat` whose samples are the
    /// source's samples scaled by `amplitude`. Handles the common
    /// case of channel-count mismatch (mono source → stereo mix
    /// format) by duplicating mono into both channels.
    private static func scaledCopy(
        of source: AVAudioPCMBuffer,
        amplitude: Float,
        targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let dest = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: source.frameLength
        ) else { return nil }
        dest.frameLength = source.frameLength

        let frameCount = Int(source.frameLength)
        let destChannels = Int(targetFormat.channelCount)
        let srcChannels = Int(source.format.channelCount)
        guard let srcData = source.floatChannelData,
              let destData = dest.floatChannelData
        else { return nil }

        for ch in 0..<destChannels {
            let srcCh = ch < srcChannels ? ch : 0  // duplicate mono
            let srcPtr = srcData[srcCh]
            let destPtr = destData[ch]
            for i in 0..<frameCount {
                destPtr[i] = srcPtr[i] * amplitude
            }
        }
        return dest
    }
}
