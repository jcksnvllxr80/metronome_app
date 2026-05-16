//
//  meter_gnomeApp.swift
//  meter-gnome
//

import SwiftUI
import MetronomeCore

@main
struct meter_gnomeApp: App {
    @State private var viewModel: MetronomeViewModel

    init() {
        // Configure AVAudioSession category at launch (category set but
        // session NOT yet activated — activation happens at engine.start()).
        AudioSessionCoordinator.shared.configure()

        // Construct the engine + audio scheduler and wire them together.
        // The scheduler holds AVAudioEngine; attach() is async, but we
        // can fire-and-forget the attach Task because nothing tries to
        // play audio until the user taps Play — which is far in the
        // future relative to one actor hop.
        let engine = MetronomeEngine()
        let scheduler = AudioScheduler()
        Task {
            await engine.attach(scheduler: scheduler)
        }
        // Wire the session coordinator to the engine so audio interruptions
        // (phone calls, Siri) and route changes (headphones unplugged)
        // drive engine.pause() / engine.resume().
        AudioSessionCoordinator.shared.attach(engine: engine)

        _viewModel = State(wrappedValue: MetronomeViewModel(engine: engine))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
