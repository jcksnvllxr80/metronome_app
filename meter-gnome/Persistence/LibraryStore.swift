//
//  LibraryStore.swift
//  meter-gnome
//
//  CRUD wrapper around `PersistedSong` + `PersistedSetlist`. Songs and
//  setlists currently have no UI surface (the Stage view is the only
//  screen), so this store ships ready for a future Library/Setlist screen
//  to drop in without re-doing the persistence layer.
//
//  Songs in the library are independent records. A setlist holds a
//  snapshot copy of each song's value (via PersistedSetlist.songsData)
//  — that way editing a library song doesn't retroactively mutate
//  setlists you saved last week.
//

import Foundation
import SwiftData
import MetronomeCore

@MainActor
final class LibraryStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Songs

    func allSongs() -> [Song] {
        let descriptor = FetchDescriptor<PersistedSong>(sortBy: [SortDescriptor(\.title)])
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.compactMap { $0.toSong() }
    }

    /// Insert or update by ID.
    func save(_ song: Song) {
        let id = song.id
        let descriptor = FetchDescriptor<PersistedSong>(predicate: #Predicate { $0.id == id })
        if let existing = (try? context.fetch(descriptor))?.first {
            context.delete(existing)
        }
        if let row = PersistedSong(from: song) {
            context.insert(row)
            try? context.save()
        }
    }

    func deleteSong(id: UUID) {
        let descriptor = FetchDescriptor<PersistedSong>(predicate: #Predicate { $0.id == id })
        if let row = (try? context.fetch(descriptor))?.first {
            context.delete(row)
            try? context.save()
        }
    }

    // MARK: - Setlists

    func allSetlists() -> [Setlist] {
        let descriptor = FetchDescriptor<PersistedSetlist>(sortBy: [SortDescriptor(\.name)])
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { $0.toSetlist() }
    }

    func save(_ setlist: Setlist) {
        let id = setlist.id
        let descriptor = FetchDescriptor<PersistedSetlist>(predicate: #Predicate { $0.id == id })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.update(from: setlist)
        } else {
            context.insert(PersistedSetlist(from: setlist))
        }
        try? context.save()
    }

    func deleteSetlist(id: UUID) {
        let descriptor = FetchDescriptor<PersistedSetlist>(predicate: #Predicate { $0.id == id })
        if let row = (try? context.fetch(descriptor))?.first {
            context.delete(row)
            try? context.save()
        }
    }
}
