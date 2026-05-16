//
//  SettingsStore.swift
//  meter-gnome
//
//  Singleton wrapper around `PersistedEngineSettings`. Loads-or-creates the
//  one row on init; exposes the current settings as a snapshot and persists
//  on every update. The view model holds a reference and pushes new
//  EngineSettings through `update(_:)` whenever the user changes a value
//  in the Settings sheet.
//

import Foundation
import SwiftData
import MetronomeCore

@MainActor
final class SettingsStore {
    private let context: ModelContext
    private let row: PersistedEngineSettings
    private(set) var current: EngineSettings

    init(context: ModelContext) {
        self.context = context
        // Load the singleton row, or create defaults if this is a first launch.
        let descriptor = FetchDescriptor<PersistedEngineSettings>()
        let existing = (try? context.fetch(descriptor)) ?? []
        if let first = existing.first {
            self.row = first
        } else {
            let new = PersistedEngineSettings()
            context.insert(new)
            self.row = new
            try? context.save()
        }
        self.current = row.toEngineSettings()
    }

    func update(_ newSettings: EngineSettings) {
        current = newSettings
        row.update(from: newSettings)
        do {
            try context.save()
        } catch {
            print("SettingsStore: save failed: \(error)")
        }
    }
}
