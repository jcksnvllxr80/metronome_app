//
//  AudioSessionCoordinator.swift
//  meter-gnome
//
//  Configures `AVAudioSession` for the app per spec §10.1 and CLAUDE.md:
//  category `.playback` with `.mixWithOthers` so playback coexists with
//  music apps + tuners.
//
//  **Sub-commit A: configuration only.** The session category is set at
//  launch but the session is NOT activated yet — that happens at
//  engine.start() time once Sub-commit B's audio scheduler is producing
//  buffers. Configuring without activating has no audible side effect on
//  the user's currently playing music.
//
//  Sub-commit C will add `interruptionNotification` and
//  `routeChangeNotification` observers per spec §16.
//

import AVFoundation

@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private var configured = false

    private init() {}

    /// Set the session category. Safe to call multiple times — only the
    /// first call configures; subsequent calls no-op. Errors are logged
    /// (the app still functions silently if configuration fails).
    func configure(mixWithOthers: Bool = true) {
        guard !configured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                options: mixWithOthers ? [.mixWithOthers] : []
            )
            configured = true
        } catch {
            print("AudioSessionCoordinator: setCategory failed: \(error)")
        }
    }
}
