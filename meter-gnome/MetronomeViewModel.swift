//
//  MetronomeViewModel.swift
//  meter-gnome
//
//  Bridges the off-main `MetronomeEngine` actor to SwiftUI's @MainActor
//  Observation world. Holds a snapshot of engine state for synchronous
//  view reads (BPM, time sig, current schedule), exposes pulse-intensity
//  + current-beat + tap-flash helpers for the live UI, and forwards user
//  actions into the engine via Task awaits.
//

import SwiftUI
import MetronomeCore

@Observable
final class MetronomeViewModel {
    let engine: MetronomeEngine

    /// Persistence handles. Optional so previews + tests can construct the
    /// view model with the engine alone (no SwiftData container needed).
    @ObservationIgnored let settingsStore: SettingsStore?
    @ObservationIgnored let libraryStore: LibraryStore?
    /// Setlist playback coordinator. Optional so previews work without
    /// the full app stack.
    @ObservationIgnored let setlistPlayer: SetlistPlayer?

    // Mirrored engine state. Optimistically updated on user action; the
    // authoritative read happens in refresh() right after.
    var bpm: BPM = BPM(120)
    var timeSignature: TimeSignature = .fourFour
    var subdivision: Subdivision = .none
    var isRunning: Bool = false
    var settings: EngineSettings = EngineSettings()
    /// Cached snapshot of the library's saved songs. Refreshed by the
    /// view model whenever a song is added, deleted, or the library
    /// sheet is presented. Empty when no LibraryStore is attached.
    var librarySongs: [Song] = []
    /// Cached snapshot of saved setlists. Same refresh pattern as
    /// `librarySongs`.
    var librarySetlists: [Setlist] = []

    // MARK: - Setlist playback state (mirrored from SetlistPlayer)

    /// Name of the currently-playing setlist, or `nil` when none.
    var playingSetlistName: String? = nil
    /// 0-based index of the active song in the playing setlist.
    var playingSongIndex: Int = -1
    /// Total songs in the playing setlist.
    var playingSetlistCount: Int = 0
    /// Title of the song the engine is currently playing (from the setlist).
    var playingSongTitle: String? = nil
    /// Whether the player is awaiting a user Play tap after a `.pause`
    /// mode advance. UI surfaces this with a subtle hint.
    var isWaitingForResume: Bool = false
    /// A snapshot of the engine's current ClickSchedule. The view reads
    /// this every animation frame via TimelineView to drive the pulse.
    /// `nil` when the engine is stopped or before the first start().
    var schedule: ClickSchedule? = nil

    /// Clock time of the most recent tap on the tap-tempo button. Drives
    /// the visual flash via `tapFlashIntensity(at:)`. `-.infinity` means
    /// "never tapped" — by definition `time - (-.infinity) > 0.150`, so
    /// flash intensity reads 0.
    var lastTapTime: TimeInterval = -.infinity

    /// `@ObservationIgnored` because tap tempo state churns on every tap
    /// and re-rendering the whole view tree on each one is wasted work —
    /// the only output that should trigger a re-render is the resulting BPM,
    /// which already goes through the `bpm` field, plus the lastTapTime
    /// which is observed explicitly.
    @ObservationIgnored
    private var tapEstimator = TapTempoEstimator()

    init(
        engine: MetronomeEngine = MetronomeEngine(),
        settingsStore: SettingsStore? = nil,
        libraryStore: LibraryStore? = nil,
        setlistPlayer: SetlistPlayer? = nil
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.libraryStore = libraryStore
        self.setlistPlayer = setlistPlayer
        // Seed `settings` synchronously from the store if available so
        // the SettingsView opens with the persisted values, not defaults.
        if let initial = settingsStore?.current {
            self.settings = initial
        }
        Task { await self.refresh() }
        // 100 ms tick so the setlist indicator reflects internal advances
        // driven by the player's own poll task. Cheap (one actor hop).
        if setlistPlayer != nil {
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    await self?.refreshSetlistPlaybackState()
                }
            }
        }
    }

    /// Pull the authoritative state off the engine actor. Cheap (one actor
    /// hop) and idempotent — safe to call after any mutation.
    func refresh() async {
        let bpm = await engine.bpm
        let ts = await engine.timeSignature
        let sub = await engine.subdivision
        let running = await engine.isRunning
        let sched = await engine.schedule
        let settings = await engine.settings
        self.bpm = bpm
        self.timeSignature = ts
        self.subdivision = sub
        self.isRunning = running
        self.schedule = sched
        self.settings = settings
    }

    // MARK: - User actions

    func nudgeBPM(by delta: Double) {
        let newBPM = BPM(bpm.value + delta)
        bpm = newBPM // optimistic — engine clamps + snaps, refresh() reconciles
        Task {
            await engine.setBPM(newBPM)
            await refresh()
        }
    }

    func togglePlay() {
        Task {
            if await engine.isRunning {
                await engine.stop()
            } else {
                await engine.start()
            }
            await refresh()
        }
    }

    /// Commit a new time signature. The engine clears any accent pattern
    /// scoped to the old meter (per spec §3.2); refresh() picks that up.
    func setTimeSignature(_ newTS: TimeSignature) {
        timeSignature = newTS // optimistic
        Task {
            await engine.setTimeSignature(newTS)
            await refresh()
        }
    }

    /// Commit a new subdivision. The engine re-anchors its schedule
    /// at clock.now (and the audio scheduler picks up the new click
    /// period on its next refill pass).
    func setSubdivision(_ newSub: Subdivision) {
        subdivision = newSub // optimistic
        Task {
            await engine.setSubdivision(newSub)
            await refresh()
        }
    }

    /// Commit new engine settings. The audio scheduler picks up
    /// masterVolume / latencyOffsetSeconds at the next refill pass (~50 ms);
    /// countIn and autoResume apply at the next start / interruption.
    /// Persists to disk synchronously via SettingsStore so the change
    /// survives the next launch.
    func setSettings(_ newSettings: EngineSettings) {
        settings = newSettings // optimistic
        settingsStore?.update(newSettings)
        Task {
            await engine.setSettings(newSettings)
            await refresh()
        }
    }

    // MARK: - Library

    /// Pull the latest songs + setlists from SwiftData. Cheap (two sorted fetches).
    func refreshLibrary() {
        librarySongs = libraryStore?.allSongs() ?? []
        librarySetlists = libraryStore?.allSetlists() ?? []
    }

    /// Save the engine's current settings as a new Song with the given title.
    /// Returns false if the LibraryStore isn't attached or the title is blank.
    @discardableResult
    func saveCurrentAsSong(title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let store = libraryStore else { return false }
        guard let song = Song(
            title: trimmed,
            bpm: bpm,
            timeSignature: timeSignature,
            subdivision: subdivision
        ) else { return false }
        store.save(song)
        refreshLibrary()
        return true
    }

    /// Insert or update a song by ID. Used by SongDetailView to persist
    /// edits to existing songs.
    func saveSong(_ song: Song) {
        libraryStore?.save(song)
        refreshLibrary()
    }

    /// Load a song's settings into the engine. Doesn't auto-start —
    /// keeps the user in control of when audio begins.
    func loadSong(_ song: Song) {
        Task {
            await engine.apply(song)
            await refresh()
        }
    }

    /// Delete a song from the library.
    func deleteSong(id: UUID) {
        libraryStore?.deleteSong(id: id)
        refreshLibrary()
    }

    /// Create an empty setlist with the given name. Returns the new
    /// setlist on success, or `nil` if the name was blank or no
    /// LibraryStore is attached. The caller can use the returned setlist
    /// to immediately push into a detail view for editing.
    @discardableResult
    func createSetlist(name: String) -> Setlist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let store = libraryStore else { return nil }
        let setlist = Setlist(name: trimmed)
        store.save(setlist)
        refreshLibrary()
        return setlist
    }

    /// Save (insert or update) a setlist by ID. Used by the detail view
    /// every time a song is added, reordered, or removed.
    func saveSetlist(_ setlist: Setlist) {
        libraryStore?.save(setlist)
        refreshLibrary()
    }

    /// Delete a setlist (does NOT delete the songs inside, which are
    /// independent library entries).
    func deleteSetlist(id: UUID) {
        libraryStore?.deleteSetlist(id: id)
        refreshLibrary()
    }

    // MARK: - Setlist playback

    /// Start sequential playback of a setlist. The player loads the first
    /// song into the engine and starts audio; auto-advance happens via
    /// the player's polling tick.
    func playSetlist(_ setlist: Setlist) {
        guard let player = setlistPlayer else { return }
        Task {
            await player.play(setlist)
            await refresh()
            await refreshSetlistPlaybackState()
        }
    }

    /// Stop setlist playback entirely. Engine stops; player state clears.
    func stopSetlist() {
        guard let player = setlistPlayer else { return }
        Task {
            await player.stop()
            await refresh()
            await refreshSetlistPlaybackState()
        }
    }

    /// Manual jump to next song in the active setlist. End of setlist
    /// stops playback.
    func nextSong() {
        guard let player = setlistPlayer else { return }
        Task {
            await player.next()
            await refresh()
            await refreshSetlistPlaybackState()
        }
    }

    /// Manual jump to previous song. No-op at start.
    func previousSong() {
        guard let player = setlistPlayer else { return }
        Task {
            await player.previous()
            await refresh()
            await refreshSetlistPlaybackState()
        }
    }

    /// Pull setlist-player state into the @Observable mirrors so the UI
    /// (Stage indicator) updates. Called after every playback action and
    /// on the polling refresh loop.
    func refreshSetlistPlaybackState() async {
        guard let player = setlistPlayer else { return }
        let isActive = await player.isActive
        let setlist = await player.setlist
        let idx = await player.currentIndex
        let song = await player.currentSong
        let waiting = await player.isWaitingForResume
        self.playingSetlistName = isActive ? setlist?.name : nil
        self.playingSongIndex = idx
        self.playingSetlistCount = setlist?.count ?? 0
        self.playingSongTitle = song?.title
        self.isWaitingForResume = waiting
    }

    /// Register a tap from the UI's tap-tempo button. Always records
    /// `lastTapTime` so the flash fires even on a single tap (which by
    /// itself doesn't yet produce a BPM estimate).
    func tap() {
        let now = SystemClock().now
        lastTapTime = now
        guard let estimate = tapEstimator.tap(at: now) else { return }
        bpm = estimate
        Task {
            await engine.setBPM(estimate)
            await refresh()
        }
    }

    // MARK: - View helpers

    /// The most-recent click at or before `time`, or `nil` if no click has
    /// fired yet (engine stopped, or `time` is before the first click).
    func currentClick(at time: TimeInterval) -> Click? {
        guard let schedule, isRunning else { return nil }
        let nextIdx = schedule.firstClickIndex(atOrAfter: time)
        guard nextIdx > 0 else { return nil }
        return schedule.click(at: nextIdx - 1)
    }

    /// Pulse intensity [0, 1] at the given clock time. 1 = on accent peak,
    /// 0 = back to base color. Implements DESIGN.md's beat pulse spec:
    /// - 10 ms hard attack
    /// - `(60 / bpm) * 0.4` second ease-out decay (quadratic falloff)
    /// - Reduce Motion: discrete 30 ms hold of full intensity, no fade.
    func pulseIntensity(at time: TimeInterval, reduceMotion: Bool) -> Double {
        guard let click = currentClick(at: time) else { return 0 }
        let timeSince = time - click.time
        if timeSince < 0 { return 0 }

        if reduceMotion {
            return timeSince < 0.030 ? 1 : 0
        }

        let attack: TimeInterval = 0.010
        let decay = (60.0 / bpm.value) * 0.4
        if timeSince < attack { return 1 }
        if timeSince < attack + decay {
            let progress = (timeSince - attack) / decay
            // Ease-out from 1 → 0: y = (1 - x)^2. Falls fast initially, then settles.
            return (1 - progress) * (1 - progress)
        }
        return 0
    }

    /// Flash intensity [0, 1] for the tap-tempo button after a tap.
    /// 150 ms linear falloff — matches the "registered" feedback expected
    /// per spec §6.1.
    func tapFlashIntensity(at time: TimeInterval) -> Double {
        let elapsed = time - lastTapTime
        if elapsed < 0 || elapsed > 0.150 { return 0 }
        return max(0, 1 - elapsed / 0.150)
    }
}
