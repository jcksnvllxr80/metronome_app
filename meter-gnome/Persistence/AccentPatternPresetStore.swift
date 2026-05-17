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

    // MARK: - Starter presets

    /// Curated starter presets across common time signatures. Used to
    /// seed the store on first launch so users have something to play
    /// with — and as reference for the accent levels available.
    static let starterPresets: [AccentPatternPreset] = {
        var out: [AccentPatternPreset] = []

        // Rock 4/4 — downbeat strong, beat 3 medium, 2 and 4 normal.
        if let p = AccentPattern(
            name: "Rock 4/4",
            timeSignature: .fourFour,
            beats: [
                .downbeat,
                .mainBeat,
                BeatConfig(accent: .loud, soundOverride: nil, pitchShift: .unison),
                .mainBeat
            ]
        ) {
            out.append(AccentPatternPreset(id: UUID(), name: "Rock 4/4", pattern: p))
        }

        // Waltz 3/4 — strong downbeat, soft 2 and 3 (the classic
        // "one-two-three" lilt).
        if let p = AccentPattern(
            name: "Waltz 3/4",
            timeSignature: TimeSignature(numerator: 3, denominator: .quarter)!,
            beats: [
                .downbeat,
                BeatConfig(accent: .soft, soundOverride: nil, pitchShift: .unison),
                BeatConfig(accent: .soft, soundOverride: nil, pitchShift: .unison),
            ]
        ) {
            out.append(AccentPatternPreset(id: UUID(), name: "Waltz 3/4", pattern: p))
        }

        // 6/8 compound — accents on 1 and 4 (2+2+2 → really 3+3 grouping
        // in compound feel).
        if let sixEight = TimeSignature(numerator: 6, denominator: .eighth),
           let p = AccentPattern(
            name: "Compound 6/8",
            timeSignature: sixEight,
            beats: [
                .downbeat,
                .mainBeat,
                .mainBeat,
                BeatConfig(accent: .loud, soundOverride: nil, pitchShift: .unison),
                .mainBeat,
                .mainBeat,
            ]
        ) {
            out.append(AccentPatternPreset(id: UUID(), name: "Compound 6/8", pattern: p))
        }

        // 7/8 odd-meter — 2+2+3 grouping (one of the standard
        // possibilities; the spec calls out multiple).
        if let sevenEight = TimeSignature(numerator: 7, denominator: .eighth),
           let p = AccentPattern(
            name: "7/8 (2+2+3)",
            timeSignature: sevenEight,
            beats: [
                .downbeat,
                .mainBeat,
                BeatConfig(accent: .loud, soundOverride: nil, pitchShift: .unison),
                .mainBeat,
                BeatConfig(accent: .loud, soundOverride: nil, pitchShift: .unison),
                .mainBeat,
                .mainBeat,
            ]
        ) {
            out.append(AccentPatternPreset(id: UUID(), name: "7/8 (2+2+3)", pattern: p))
        }

        // 5/4 — Brubeck-style "Take Five" 3+2 grouping.
        if let fiveFour = TimeSignature(numerator: 5, denominator: .quarter),
           let p = AccentPattern(
            name: "5/4 (3+2)",
            timeSignature: fiveFour,
            beats: [
                .downbeat,
                .mainBeat,
                .mainBeat,
                BeatConfig(accent: .loud, soundOverride: nil, pitchShift: .unison),
                .mainBeat,
            ]
        ) {
            out.append(AccentPatternPreset(id: UUID(), name: "5/4 (3+2)", pattern: p))
        }

        return out
    }()

    /// Add every starter preset (with fresh UUIDs each call so re-running
    /// is non-destructive — you'd just end up with duplicates). The view
    /// model should only call this when the user explicitly asks.
    @discardableResult
    func addStarterPresets() -> Int {
        var added = 0
        for preset in Self.starterPresets {
            // Fresh UUID per add so re-running doesn't collide.
            let copy = AccentPatternPreset(id: UUID(), name: preset.name, pattern: preset.pattern)
            if save(copy) { added += 1 }
        }
        return added
    }
}
