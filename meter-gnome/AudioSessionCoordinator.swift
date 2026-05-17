//
//  AudioSessionCoordinator.swift
//  meter-gnome
//
//  Configures `AVAudioSession` and routes interruption + route-change
//  events into the engine per spec §10.1 + §16:
//
//  - Category `.playback` with `.mixWithOthers` (coexists with music apps
//    and tuners).
//  - On interruption began (phone call, Siri): engine.pause().
//  - On interruption ended with .shouldResume AND
//    settings.autoResumeAfterInterruption == true: engine.resume().
//  - On headphone unplug (.oldDeviceUnavailable): engine.pause() per HIG
//    (don't blast click out of the device speaker).
//
//  The session category is set at app launch but NOT activated until the
//  audio scheduler's start() runs (avoids interrupting user's music
//  while the app is idle).
//

import AVFoundation
import MetronomeCore

@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    /// Tracks whether the category has been set at least once. The
    /// initial `configure(...)` flips this so subsequent calls can
    /// detect that they're a reconfiguration (mixWithOthers toggled
    /// at runtime) rather than a fresh install.
    private var configured = false
    /// Last mixWithOthers value applied to the session, so a
    /// no-op reconfigure (same value) doesn't bounce the category.
    private var lastMixWithOthers: Bool?
    private var observing = false
    private weak var engine: MetronomeEngine?

    private init() {}

    /// Attach the engine so interruption / route-change events can drive
    /// `pause()` / `resume()`. Safe to call before or after `configure()`.
    func attach(engine: MetronomeEngine) {
        self.engine = engine
        startObserving()
    }

    /// Set the session category. Safe to call multiple times — calls
    /// after the first one re-set the category if (and only if)
    /// `mixWithOthers` has changed, so the user toggling it in
    /// Settings takes effect mid-session without a relaunch. Errors
    /// are logged (the app still functions silently if configuration
    /// fails).
    ///
    /// When `mixWithOthers` is true, our session coexists with the
    /// Music app, podcast players, tuners, etc. — we never displace
    /// their Now Playing slot, which means iOS won't surface our
    /// lock-screen card either. Set to false to claim primary audio
    /// (and Now Playing), at the cost of pausing whatever else was
    /// playing when meter-gnome starts.
    func configure(mixWithOthers: Bool) {
        guard mixWithOthers != lastMixWithOthers else { return }
        lastMixWithOthers = mixWithOthers
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

    // MARK: - Notification observers

    private func startObserving() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleInterruption(note)
            }
        }
        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleRouteChange(note)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            Task { [weak engine] in
                await engine?.pause()
            }
        case .ended:
            // Only auto-resume when BOTH the system says we may
            // (.shouldResume option) AND the user has opted into it.
            let shouldResume: Bool = {
                guard let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt
                else { return false }
                return AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                    .contains(.shouldResume)
            }()
            if shouldResume {
                Task { [weak engine] in
                    guard let engine, await engine.settings.autoResumeAfterInterruption else { return }
                    await engine.resume()
                }
            }
        @unknown default: break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)
        else { return }

        // Apple HIG default: when the previous audio device disappears
        // (headphones unplugged, BT disconnected), pause rather than re-
        // routing the click stream out the device's main speaker.
        if reason == .oldDeviceUnavailable {
            Task { [weak engine] in
                await engine?.pause()
            }
        }
    }
}
