//
//  AccentPatternPresetStore.swift
//  meter-gnome
//
//  CRUD wrapper for the named accent-pattern preset library (spec §3.2).
//  Patterns are persisted independent of songs so the same "rock 4/4"
//  or "swing 7/8" pattern can be reused across many songs.
//

import Foundation
import SwiftData
import MetronomeCore

/// One row in the preset library — pairs a stable UUID + display name
/// with the pattern itself. The `name` is stored alongside the pattern
/// data so it survives even if `AccentPattern.name` ever drifts.
struct AccentPatternPreset: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var pattern: AccentPattern
}

@MainActor
final class AccentPatternPresetStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// All presets, sorted by name. Used by the picker in the accent
    /// editor + any future "patterns" tab in Library.
    func all() -> [AccentPatternPreset] {
        let descriptor = FetchDescriptor<PersistedAccentPatternPreset>(
            sortBy: [SortDescriptor(\.name)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.compactMap { row in
            guard let pattern = row.toPattern() else { return nil }
            return AccentPatternPreset(id: row.id, name: row.name, pattern: pattern)
        }
    }

    /// Presets scoped to a specific time signature — what the accent
    /// editor's "Load preset" picker should show (a 7/8 pattern is
    /// meaningless in 4/4 per spec §3.2).
    func all(matching timeSignature: TimeSignature) -> [AccentPatternPreset] {
        all().filter { $0.pattern.timeSignature == timeSignature }
    }

    /// Insert or update by ID. Returns false if the pattern fails to
    /// encode (shouldn't happen).
    @discardableResult
    func save(_ preset: AccentPatternPreset) -> Bool {
        let id = preset.id
        let descriptor = FetchDescriptor<PersistedAccentPatternPreset>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            context.delete(existing)
        }
        guard let row = PersistedAccentPatternPreset(
            id: preset.id,
            name: preset.name,
            pattern: preset.pattern
        ) else { return false }
        context.insert(row)
        try? context.save()
        return true
    }

    func delete(id: UUID) {
        let descriptor = FetchDescriptor<PersistedAccentPatternPreset>(
            predicate: #Predicate { $0.id == id }
        )
        if let row = (try? context.fetch(descriptor))?.first {
            context.delete(row)
            try? context.save()
        }
    }
}
