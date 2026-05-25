//
//  NowPlayingCoordinator.swift
//  meter-gnome
//
//  Publishes lock-screen + Control Center + AirPods playback metadata via
//  `MPNowPlayingInfoCenter` and handles remote commands (play, pause,
//  toggle, next/previous in setlists) via `MPRemoteCommandCenter`. Spec
//  §16; closes a Phase 1 gap.
//
//  Title precedence: setlist song > standalone-loaded song title (when
//  surfaced — TODO) > "Metronome". Artist line always includes BPM.
//  next/previous commands are disabled when no setlist is playing.
//
//  Real device only — the iOS simulator doesn't reliably render the
//  Now Playing card or honour Remote Command Center actions.
//

import MediaPlayer
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import MetronomeCore

@MainActor
final class NowPlayingCoordinator {
    static let shared = NowPlayingCoordinator()

    private weak var viewModel: MetronomeViewModel?
    private var pollTask: Task<Void, Never>?
    private var commandsRegistered = false
    /// When true, the next publish forces a fresh dictionary push
    /// even if the snapshot hasn't changed. Used by external
    /// triggers (audio session activation, engine-state changes)
    /// to break out of the dedupe so iOS sees a "live" entry the
    /// moment audio starts.
    private var forceNextPublish = false
    /// Lazily-resolved MPMediaItemArtwork wrapping the app icon. Built
    /// once and cached — Now Playing reads the same image on every
    /// publish.
    private lazy var artwork: MPMediaItemArtwork? = {
        guard let image = PlatformImage(named: "AppIcon") else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }()

    // Last published snapshot — used to skip redundant updates so the poll
    // loop isn't hammering MPNowPlayingInfoCenter every tick.
    private struct Snapshot: Equatable {
        var isRunning: Bool
        var bpm: Int
        var title: String
        var artist: String
        var setlistActive: Bool
    }
    private var lastPublished: Snapshot?

    private init() {}

    /// Attach the view model. The coordinator reads engine state through
    /// the view model's mirrored fields rather than hopping the engine
    /// actor — Now Playing updates aren't authoritative; lag of 100 ms is
    /// fine. Safe to call multiple times.
    func attach(viewModel: MetronomeViewModel) {
        self.viewModel = viewModel
        registerCommands()
        startPolling()
    }

    /// Force the next publish pass to push the dictionary again even
    /// if the snapshot looks unchanged. ContentView calls this when
    /// `viewModel.isRunning` flips so iOS sees the live entry at the
    /// instant audio begins, rather than waiting up to 200ms for the
    /// next poll tick. Bypasses the dedupe guard.
    func forceRepublish() {
        forceNextPublish = true
    }

    // MARK: - Remote Command Center

    private func registerCommands() {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let center = MPRemoteCommandCenter.shared()

        // Explicitly enable the transport commands. addTarget enables
        // them implicitly per Apple docs, but in practice (esp. on
        // iOS 17+) being explicit ensures the lock-screen render
        // path picks them up; without this some users see a card
        // with greyed-out buttons.
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            guard let vm = self?.viewModel else { return .commandFailed }
            if !vm.isRunning { vm.togglePlay() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let vm = self?.viewModel else { return .commandFailed }
            if vm.isRunning { vm.togglePlay() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let vm = self?.viewModel else { return .commandFailed }
            vm.togglePlay()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let vm = self?.viewModel,
                  vm.playingSetlistName != nil else { return .noActionableNowPlayingItem }
            vm.nextSong()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let vm = self?.viewModel,
                  vm.playingSetlistName != nil else { return .noActionableNowPlayingItem }
            vm.previousSong()
            return .success
        }
    }

    // MARK: - Now Playing info

    private func startPolling() {
        pollTask?.cancel()
        // 200 ms — fast enough to feel live on the lock screen when
        // tempo nudges; cheap enough that we're not thrashing the
        // shared info center. State-change dedupe in publish() keeps
        // most ticks no-op.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.publish()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func publish() {
        guard let vm = viewModel else { return }
        let setlistActive = vm.playingSetlistName != nil
        // Title precedence: setlist > standalone-loaded > generic.
        let title: String = vm.playingSongTitle
            ?? vm.loadedSongTitle
            ?? "Metronome"
        let artist: String
        if let setlistName = vm.playingSetlistName {
            let n = vm.playingSongIndex + 1
            artist = "\(setlistName) · \(n)/\(vm.playingSetlistCount) · \(vm.bpm.displayInt) BPM"
        } else {
            artist = "\(vm.bpm.displayInt) BPM"
        }
        let snapshot = Snapshot(
            isRunning: vm.isRunning,
            bpm: vm.bpm.displayInt,
            title: title,
            artist: artist,
            setlistActive: setlistActive
        )
        if snapshot == lastPublished, !forceNextPublish { return }
        forceNextPublish = false
        lastPublished = snapshot

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        info[MPNowPlayingInfoPropertyPlaybackRate] = snapshot.isRunning ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        // Mark this as a live audio stream — metronome output has no
        // defined duration, so iOS shouldn't draw scrubber UI or
        // expect elapsed/total time fields. Without this flag iOS 17+
        // will sometimes suppress the lock-screen card entirely when
        // the app uses `.mixWithOthers` (which we do — spec §10.1).
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        // Some iOS builds still expect elapsed time to be present even
        // on a live stream; 0 is the canonical "no offset" value.
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: 0.0)
        // Setting duration = 0 alongside IsLiveStream is the documented
        // signal pattern for a live audio source per Apple's MPMediaItem
        // guidance. Some lock-screen render paths key off the presence
        // of this field to decide which transport UI to show.
        info[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: 0.0)
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        // Set playbackState FIRST so the nowPlayingInfo arrives at a
        // center that already knows we're playing — some iOS builds
        // appear to use this state when deciding whether to surface
        // the lock-screen card on the dictionary update.
        MPNowPlayingInfoCenter.default().playbackState = snapshot.isRunning ? .playing : .paused
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = setlistActive
        center.previousTrackCommand.isEnabled = setlistActive
    }
}
