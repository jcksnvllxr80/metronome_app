//
//  UserSoundStore.swift
//  meter-gnome
//
//  Persistence + sandbox file IO for user-imported sounds (spec §4.2).
//  Acts as the bridge between the UI (Settings → Manage Imported Sounds)
//  and the audio path (`UserSoundRegistry` in `MetronomeCore`).
//
//  Two responsibilities:
//   - SwiftData CRUD on `PersistedUserSound` rows
//   - File IO: copy imported files into `Documents/UserSounds/`, look up
//     absolute URLs by filename, delete files on row removal.
//
//  The audio scheduler queries this store to populate the
//  `UserSoundRegistry` on launch + whenever the user adds/removes/
//  retrims an imported sound.
//

import Foundation
import SwiftData
import AVFoundation
import MetronomeCore

final class UserSoundStore {
    private let context: ModelContext
    /// Directory inside the app sandbox where imported files live.
    /// Created lazily on first access — keeps a clean install free of
    /// empty directories.
    private let soundsDirectory: URL

    init(context: ModelContext) {
        self.context = context
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.soundsDirectory = documents.appendingPathComponent("UserSounds", isDirectory: true)
    }

    /// Absolute URL for a sound's audio file. Callers should treat the
    /// path as opaque — only `UserSoundRegistry` and this store touch
    /// it directly.
    func url(for sound: UserSound) -> URL {
        soundsDirectory.appendingPathComponent(sound.filename)
    }

    /// All currently-imported sounds, sorted by display name for
    /// stable picker order.
    func allSounds() -> [UserSound] {
        let descriptor = FetchDescriptor<PersistedUserSound>(
            sortBy: [SortDescriptor(\.name)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { $0.toUserSound() }
    }

    /// Import an audio file from an external location (Files app
    /// picker URL). Validates spec §4.2 constraints, copies into the
    /// sandbox, and inserts the persisted row.
    ///
    /// Returns the inserted `UserSound` on success. Throws
    /// `UserSoundImportError` on any constraint violation — caller is
    /// responsible for surfacing the message to the user.
    func importSound(from sourceURL: URL, displayName: String? = nil) throws -> UserSound {
        // 1. Extension check. Spec §4.2 accepts wav / aiff / aif / caf.
        let lowerExt = sourceURL.pathExtension.lowercased()
        let allowedExtensions = Set(["wav", "aif", "aiff", "caf"])
        guard allowedExtensions.contains(lowerExt) else {
            throw UserSoundImportError.unsupportedFormat
        }

        // 2. File-size check. fileSize is fetched from the URL's
        //    resourceValues — works for security-scoped URLs as long
        //    as the caller has already started + will stop the scope.
        let fileSize: Int = {
            let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey])
            return values?.fileSize ?? 0
        }()
        guard fileSize <= UserSoundLimits.maxFileSizeBytes, fileSize > 0 else {
            throw UserSoundImportError.fileTooLarge(bytes: fileSize)
        }

        // 3. Duration check. AVAudioFile is the cheapest way to read
        //    frameCount + sampleRate without decoding the full file.
        let duration: TimeInterval
        do {
            let file = try AVAudioFile(forReading: sourceURL)
            duration = TimeInterval(file.length) / file.processingFormat.sampleRate
        } catch {
            throw UserSoundImportError.couldNotDecode
        }
        guard duration <= UserSoundLimits.maxDurationSeconds, duration > 0 else {
            throw UserSoundImportError.durationTooLong(seconds: duration)
        }

        // 4. Copy file into sandbox under a new UUID. Keeping the
        //    extension preserves the file type so AVAudioFile can
        //    re-open it without sniffing.
        try createSoundsDirectoryIfNeeded()
        let id = UUID()
        let destFilename = "\(id.uuidString).\(lowerExt)"
        let destURL = soundsDirectory.appendingPathComponent(destFilename)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw UserSoundImportError.fileSystem(error.localizedDescription)
        }

        // 5. Persist row + return the value.
        let baseName = (displayName ?? sourceURL.deletingPathExtension().lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sound = UserSound(
            id: id,
            name: baseName.isEmpty ? "Imported Sound" : baseName,
            filename: destFilename,
            volumeTrim: 1.0
        )
        context.insert(PersistedUserSound(from: sound))
        try? context.save()
        return sound
    }

    /// Update an existing sound's name / volume trim. Does NOT
    /// re-import the audio file — the filename + UUID stay put.
    func update(_ sound: UserSound) {
        let id = sound.id
        let descriptor = FetchDescriptor<PersistedUserSound>(predicate: #Predicate { $0.id == id })
        if let row = (try? context.fetch(descriptor))?.first {
            row.update(from: sound)
            try? context.save()
        }
    }

    /// Remove the persisted row AND the on-disk file. Silently no-ops
    /// when either side is already gone (idempotent).
    func deleteSound(id: UUID) {
        let descriptor = FetchDescriptor<PersistedUserSound>(predicate: #Predicate { $0.id == id })
        if let row = (try? context.fetch(descriptor))?.first {
            let fileURL = soundsDirectory.appendingPathComponent(row.filename)
            try? FileManager.default.removeItem(at: fileURL)
            context.delete(row)
            try? context.save()
        }
    }

    private func createSoundsDirectoryIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: soundsDirectory.path) {
            try FileManager.default.createDirectory(
                at: soundsDirectory,
                withIntermediateDirectories: true
            )
        }
    }
}
