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
import MetronomeCore

@MainActor
final class NowPlayingCoordinator {
    static let shared = NowPlayingCoordinator()

    private weak var viewModel: MetronomeViewModel?
    private var pollTask: Task<Void, Never>?
    private var commandsRegistered = false

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

    // MARK: - Remote Command Center

    private func registerCommands() {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let center = MPRemoteCommandCenter.shared()

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
        guard snapshot != lastPublished else { return }
        lastPublished = snapshot

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        info[MPNowPlayingInfoPropertyPlaybackRate] = snapshot.isRunning ? 1.0 : 0.0
        // Setting a non-nil dict keeps our entry in the Now Playing carousel
        // even when paused; clearing it would drop us out.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = snapshot.isRunning ? .playing : .paused

        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = setlistActive
        center.previousTrackCommand.isEnabled = setlistActive
    }
}
