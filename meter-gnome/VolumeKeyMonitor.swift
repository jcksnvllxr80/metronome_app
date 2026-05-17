//
//  VolumeKeyMonitor.swift
//  meter-gnome
//
//  Hardware volume key → start/stop bridge (spec §10.4).
//
//  iOS doesn't provide a first-class API for intercepting volume button
//  presses; the standard workaround is to KVO observe
//  `AVAudioSession.outputVolume` and treat any change as a start/stop
//  trigger. The volume HUD still appears (suppressing it requires private
//  API that App Store review rejects, and Apple has been steadily
//  closing those holes anyway), and the underlying volume change is
//  still applied — but the trigger fires reliably across iOS 17/26.
//
//  Activation is gated on `settings.useVolumeKeysForStartStop` so the
//  feature is fully opt-in. When the toggle flips off, the monitor
//  removes its observer and the system volume buttons behave normally
//  again.
//
//  Real device only — the simulator's volume-button surface doesn't
//  fire AVAudioSession volume KVO. This class is structurally correct
//  but unverified on real hardware as of the v0.32.x build window.
//

import Foundation
import AVFoundation
import UIKit
import MediaPlayer

@MainActor
final class VolumeKeyMonitor {
    private weak var viewModel: MetronomeViewModel?
    private var observation: NSKeyValueObservation?
    /// Last observed volume — used to ignore the first KVO callback
    /// that fires immediately on attaching the observer (it carries
    /// the initial value, not a user press).
    private var lastVolume: Float = 0
    /// Hidden `MPVolumeView` parented off-screen. Required to keep
    /// `AVAudioSession.outputVolume` KVO active in some iOS versions —
    /// without one mounted in the view hierarchy, the session won't
    /// publish changes reliably.
    private var hiddenVolumeView: MPVolumeView?
    private var enabled: Bool = false

    init() {}

    /// Attach the view model so press events have somewhere to land.
    /// Safe to call multiple times; the second call rebinds.
    func attach(viewModel: MetronomeViewModel) {
        self.viewModel = viewModel
    }

    /// Enable or disable the monitor. Idempotent. When enabled,
    /// attaches the session KVO + parks a hidden MPVolumeView in
    /// the key window so iOS keeps publishing volume changes.
    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            installHiddenVolumeView()
            attachObservation()
        } else {
            detachObservation()
            removeHiddenVolumeView()
        }
    }

    private func attachObservation() {
        let session = AVAudioSession.sharedInstance()
        lastVolume = session.outputVolume
        // Use `.new` so the change handler reads the post-press volume.
        // `.initial` is intentionally omitted so we don't fire a phantom
        // "start" event on enable.
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self,
                  let newValue = change.newValue,
                  newValue != self.lastVolume
            else { return }
            self.lastVolume = newValue
            // Hop onto the main actor to call the view model. The
            // KVO callback isn't isolated; without the explicit hop
            // we'd violate the @MainActor isolation of the VM.
            Task { @MainActor in
                self.viewModel?.togglePlay()
            }
        }
    }

    private func detachObservation() {
        observation?.invalidate()
        observation = nil
    }

    private func installHiddenVolumeView() {
        guard hiddenVolumeView == nil,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
        else { return }
        // -1000pt off-screen + zero alpha keeps the slider invisible
        // and untouchable while still being part of the hierarchy.
        let mpv = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        mpv.alpha = 0.001
        mpv.isUserInteractionEnabled = false
        window.addSubview(mpv)
        hiddenVolumeView = mpv
    }

    private func removeHiddenVolumeView() {
        hiddenVolumeView?.removeFromSuperview()
        hiddenVolumeView = nil
    }
}
