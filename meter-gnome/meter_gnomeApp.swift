//
//  meter_gnomeApp.swift
//  meter-gnome
//

import SwiftUI
import SwiftData
import MetronomeCore

@main
struct meter_gnomeApp: App {
    @State private var viewModel: MetronomeViewModel
    private let modelContainer: ModelContainer

    init() {
        // SwiftData container — holds the user's settings + library data.
        // Fatal on failure: without persistence, the app's value proposition
        // (settings + songs surviving relaunch) is broken; better to crash
        // loudly than silently lose state.
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: PersistedEngineSettings.self,
                    PersistedSong.self,
                    PersistedSetlist.self
            )
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
        self.modelContainer = container

        // Load persisted settings up front so the engine is constructed with
        // them — avoids a brief flash of default values on launch.
        let context = ModelContext(container)
        let settingsStore = SettingsStore(context: context)
        let libraryStore = LibraryStore(context: context)

        // Audio
        AudioSessionCoordinator.shared.configure()
        let engine = MetronomeEngine(settings: settingsStore.current)
        let scheduler = AudioScheduler()
        Task {
            await engine.attach(scheduler: scheduler)
        }
        AudioSessionCoordinator.shared.attach(engine: engine)

        // Setlist playback coordinator — watches engine clock + drives
        // song transitions per the active setlist's advance mode.
        let setlistPlayer = SetlistPlayer(engine: engine)

        _viewModel = State(wrappedValue: MetronomeViewModel(
            engine: engine,
            settingsStore: settingsStore,
            libraryStore: libraryStore,
            setlistPlayer: setlistPlayer
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .modelContainer(modelContainer)
    }
}
