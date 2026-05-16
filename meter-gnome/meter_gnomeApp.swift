//
//  meter_gnomeApp.swift
//  meter-gnome
//

import SwiftUI

@main
struct meter_gnomeApp: App {
    init() {
        // Configure AVAudioSession category at launch. Doesn't activate
        // the session yet — that happens when audio actually plays
        // (Sub-commit B). Failure is logged but non-fatal: the app still
        // runs silently and the visual pulse keeps working.
        AudioSessionCoordinator.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
