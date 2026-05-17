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
import UIKit
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
    /// Practice-session log store. Optional so previews + tests still
    /// construct the view model without a SwiftData container.
    @ObservationIgnored let practiceSessionStore: PracticeSessionStore?
    /// Named accent-pattern preset library (spec §3.2). Optional so
    /// previews + tests can construct the view model without one.
    @ObservationIgnored let accentPatternPresetStore: AccentPatternPresetStore?

    // Practice-session tracking. Non-nil while a session is in progress;
    // set when the engine transitions stopped→running, written + cleared
    // when it transitions running→stopped (NOT on pause — phone-call
    // interruptions keep the session continuous).
    @ObservationIgnored private var sessionStartedAt: Date? = nil
    @ObservationIgnored private var sessionStartBPM: BPM? = nil
    /// Min/max BPM observed during the active session (updated in
    /// refresh() while the session is alive). Used to populate
    /// PracticeSession.bpmMin/bpmMax at finalize.
    @ObservationIgnored private var sessionMinBPM: BPM? = nil
    @ObservationIgnored private var sessionMaxBPM: BPM? = nil
    @ObservationIgnored private var sessionSongTitleSnapshot: String? = nil
    @ObservationIgnored private var sessionSetlistNameSnapshot: String? = nil
    @ObservationIgnored private var wasRunning: Bool = false

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
    /// Cached snapshot of recorded practice sessions (spec §11). Refreshed
    /// when the Stats tab appears.
    var practiceSessions: [PracticeSession] = []
    /// Cached snapshot of named accent-pattern presets (spec §3.2).
    /// Refreshed when the accent editor opens.
    var accentPatternPresets: [AccentPatternPreset] = []

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

    /// Mirror of the engine's active tempo automation. Drives the Stage
    /// ramp indicator. `nil` when no ramp is configured (the common case).
    var automation: TempoAutomation? = nil

    /// Title of the song most recently loaded via `loadSong(_:)`. Used by
    /// the Stage "loaded song" indicator and the Now Playing card so the
    /// user can tell which song is active without opening the Library.
    ///
    /// Cleared when a setlist starts (setlist playback takes over the
    /// "now playing" metadata via `playingSongTitle`), when the user
    /// loads a different song, or when `clearLoadedSong()` is called.
    /// Engine state edits (BPM, time signature, subdivision tweaks) do
    /// NOT clear it — the user is still "playing this song," just with
    /// adjustments.
    var loadedSongTitle: String? = nil

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
        setlistPlayer: SetlistPlayer? = nil,
        practiceSessionStore: PracticeSessionStore? = nil,
        accentPatternPresetStore: AccentPatternPresetStore? = nil
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.libraryStore = libraryStore
        self.setlistPlayer = setlistPlayer
        self.practiceSessionStore = practiceSessionStore
        self.accentPatternPresetStore = accentPatternPresetStore
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
        let paused = await engine.isPaused
        let sched = await engine.schedule
        let settings = await engine.settings
        let automation = await engine.automation
        self.bpm = bpm
        self.timeSignature = ts
        self.subdivision = sub
        self.isRunning = running
        self.schedule = sched
        self.settings = settings
        self.automation = automation

        trackPracticeSession(running: running, paused: paused, currentBPM: bpm)
        updateIdleTimer(running: running)
    }

    /// Keep the screen awake while the engine is playing if the user
    /// has the setting on (spec §10.2). Phone-on-music-stand scenario:
    /// the display sleeping mid-song is bad. Off by default would be
    /// safer for battery, but the spec asks for default-on and that
    /// matches the "stage-confident instrument" identity.
    private func updateIdleTimer(running: Bool) {
        guard settings.keepScreenAwakeDuringPlayback else {
            // If the user has the setting off, the idle timer should
            // always be at its default (enabled) — even mid-playback.
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        UIApplication.shared.isIdleTimerDisabled = running
    }

    // MARK: - Practice-session tracking (spec §11)

    /// Detect stopped↔running transitions and record one PracticeSession
    /// per genuine engine stop. Pause/resume during a phone-call
    /// interruption is treated as part of the same session — the session
    /// only ends when `isRunning` goes false AND `isPaused` is also
    /// false (i.e. the engine was stopped, not paused).
    private func trackPracticeSession(running: Bool, paused: Bool, currentBPM: BPM) {
        defer { wasRunning = running }
        // Update min/max anytime a session is in-flight (whether or not
        // the engine just transitioned). Catches manual BPM nudges,
        // tempo-automation drift, MIDI-received tempo, etc.
        if sessionStartedAt != nil {
            sessionMinBPM = sessionMinBPM.map { min($0, currentBPM) } ?? currentBPM
            sessionMaxBPM = sessionMaxBPM.map { max($0, currentBPM) } ?? currentBPM
        }
        // Started a new session
        if !wasRunning && running && sessionStartedAt == nil {
            sessionStartedAt = Date()
            sessionStartBPM = currentBPM
            sessionMinBPM = currentBPM
            sessionMaxBPM = currentBPM
            sessionSongTitleSnapshot = playingSongTitle ?? loadedSongTitle
            sessionSetlistNameSnapshot = playingSetlistName
            return
        }
        // Stopped (NOT paused) → finalize the session
        if wasRunning && !running && !paused, let startedAt = sessionStartedAt {
            let session = PracticeSession(
                startedAt: startedAt,
                endedAt: Date(),
                bpmAtStart: sessionStartBPM ?? currentBPM,
                bpmAtStop: currentBPM,
                bpmMin: sessionMinBPM,
                bpmMax: sessionMaxBPM,
                songTitle: sessionSongTitleSnapshot,
                setlistName: sessionSetlistNameSnapshot
            )
            practiceSessionStore?.record(session)
            sessionStartedAt = nil
            sessionStartBPM = nil
            sessionMinBPM = nil
            sessionMaxBPM = nil
            sessionSongTitleSnapshot = nil
            sessionSetlistNameSnapshot = nil
        }
    }

    // MARK: - User actions

    /// Set BPM to a specific value. Used by the Italian tempo preset
    /// picker (spec §6.2) and any other "jump to BPM" affordance.
    /// Engine clamps and snaps via BPM.init; refresh() reconciles.
    func setBPM(_ newBPM: BPM) {
        bpm = newBPM // optimistic
        Task {
            await engine.setBPM(newBPM)
            await refresh()
        }
    }

    func nudgeBPM(by delta: Double) {
        let newBPM = BPM(bpm.value + delta)
        bpm = newBPM // optimistic — engine clamps + snaps, refresh() reconciles
        Task {
            await engine.setBPM(newBPM)
            await refresh()
        }
    }

    /// User-facing BPM string honoring the `bpmPrecisionMode` setting
    /// (spec §10.3): "120" by default, "120.5" when precision mode is
    /// on. The view layer reads this instead of `bpm.displayInt`
    /// directly so the toggle in Settings flows everywhere.
    var bpmDisplay: String {
        if settings.bpmPrecisionMode {
            return String(format: "%.1f", bpm.value)
        }
        return "\(bpm.displayInt)"
    }

    /// Per-tap delta for the nudge buttons. 0.1 BPM in precision mode,
    /// 1 BPM otherwise.
    var bpmNudgeStep: Double {
        settings.bpmPrecisionMode ? 0.1 : 1.0
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

    /// Pull the practice-session log from the store. Called by the
    /// Stats tab onAppear; cheap (no UI work, one FetchDescriptor).
    func refreshPracticeSessions() {
        practiceSessions = practiceSessionStore?.all() ?? []
    }

    // MARK: - Accent pattern preset library (spec §3.2)

    func refreshAccentPatternPresets() {
        accentPatternPresets = accentPatternPresetStore?.all() ?? []
    }

    /// Save a pattern as a new preset under the given name. Trims
    /// whitespace and rejects blanks. Returns the new preset on success.
    @discardableResult
    func saveAccentPatternPreset(name: String, pattern: AccentPattern) -> AccentPatternPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let store = accentPatternPresetStore else { return nil }
        let preset = AccentPatternPreset(id: UUID(), name: trimmed, pattern: pattern)
        guard store.save(preset) else { return nil }
        refreshAccentPatternPresets()
        return preset
    }

    func deleteAccentPatternPreset(id: UUID) {
        accentPatternPresetStore?.delete(id: id)
        refreshAccentPatternPresets()
    }

    /// Seed the preset library with the curated starter set. Idempotent
    /// in spirit (each call generates new UUIDs so the user can re-run
    /// to top up if they've deleted some), but the UI should call this
    /// at most once on user request to avoid duplicate rows.
    @discardableResult
    func addStarterAccentPresets() -> Int {
        guard let store = accentPatternPresetStore else { return 0 }
        let added = store.addStarterPresets()
        refreshAccentPatternPresets()
        return added
    }

    /// Discard the entire practice-session history. Used by the Stats
    /// tab's clear-history action. Returns the count deleted.
    @discardableResult
    func clearPracticeHistory() -> Int {
        let count = practiceSessionStore?.deleteAll() ?? 0
        practiceSessions = []
        return count
    }

    /// CSV export of the current `practiceSessions` snapshot. Pair this
    /// with a SwiftUI ShareLink to let the user save / send the file.
    func practiceSessionsCSV() -> String {
        practiceSessions.csv
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
        loadedSongTitle = song.title
        Task {
            await engine.apply(song)
            await refresh()
        }
    }

    /// Forget the currently-loaded song (Stage indicator disappears).
    /// The engine's BPM / meter / subdivision are left alone — this is
    /// only about the displayed metadata, not playback state.
    func clearLoadedSong() {
        loadedSongTitle = nil
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
        // Setlist takes over the "now playing" metadata via playingSongTitle.
        // Clear the standalone-load title so the Stage doesn't show both.
        loadedSongTitle = nil
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
