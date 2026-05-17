//
//  PracticeSessionStore.swift
//  meter-gnome
//
//  SwiftData CRUD wrapper for practice-session history (spec §11).
//  Append-only by design — the engine writes one row per completed
//  session via `record(_:)`. The stats screen reads via `all()` /
//  `since(_:)`; CSV export goes through MetronomeCore's `csv` extension.
//
//  Sessions shorter than `minPersistedDuration` are dropped at record
//  time to keep noise out of the log (accidental Play-Stop taps, etc.).
//

import Foundation
import SwiftData
import MetronomeCore

@MainActor
final class PracticeSessionStore {
    /// Sessions shorter than this are not persisted. 30 seconds is the
    /// shortest window a user would actually "practice" — anything below
    /// is almost certainly an accidental tap.
    static let minPersistedDuration: TimeInterval = 30

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// All sessions, newest first. Used by the stats screen.
    func all() -> [PracticeSession] {
        let descriptor = FetchDescriptor<PersistedPracticeSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { $0.toPracticeSession() }
    }

    /// Sessions started at or after `date`. The stats screen uses this
    /// for today / this-week / this-month windows without pulling the
    /// full history client-side.
    func since(_ date: Date) -> [PracticeSession] {
        let descriptor = FetchDescriptor<PersistedPracticeSession>(
            predicate: #Predicate { $0.startedAt >= date },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { $0.toPracticeSession() }
    }

    /// Append a session to the log, unless it's shorter than the
    /// `minPersistedDuration` threshold. Returns whether the row was
    /// actually written — useful for tests and for surfacing "session
    /// too short to count" feedback in the future.
    @discardableResult
    func record(_ session: PracticeSession) -> Bool {
        guard session.duration >= Self.minPersistedDuration else { return false }
        context.insert(PersistedPracticeSession(from: session))
        try? context.save()
        return true
    }

    /// Drop everything. Hooked into the stats screen's "clear history"
    /// action. Returns the count deleted.
    @discardableResult
    func deleteAll() -> Int {
        let descriptor = FetchDescriptor<PersistedPracticeSession>()
        let rows = (try? context.fetch(descriptor)) ?? []
        for row in rows {
            context.delete(row)
        }
        try? context.save()
        return rows.count
    }
}
