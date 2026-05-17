import Foundation

/// Coordinates sequential playback through a `Setlist`. Owns the
/// "currently playing song" pointer, watches the engine's clock for
/// end-of-song based on each song's `duration`, and transitions to the
/// next song honoring the setlist's `advanceMode`.
///
/// Playback model:
/// - Songs with `duration == nil` never auto-advance — only `next()`,
///   `previous()`, or `stop()` ends them.
/// - With `.pause`: engine stops after the current song; the next song's
///   settings are loaded but not started. The user presses Play on Stage
///   to start it. Duration tracking resumes when the engine becomes
///   `isRunning` again.
/// - With `.countdown(measures:)`: engine plays N measures of count-in at
///   the next song's tempo, then the next song.
/// - With `.immediate`: engine continues into the next song with no gap.
///
/// End of setlist: engine stops, player state clears.
public actor SetlistPlayer {
    public private(set) weak var engine: MetronomeEngine?
    /// Weak reference to the section player. When the current setlist
    /// song `.isMultiSection`, `startCurrentSong` routes through this
    /// player with a completion callback so section auto-advance drives
    /// end-of-song detection (instead of `song.duration`). Optional —
    /// when nil, multi-section songs fall back to flat playback at the
    /// song's top-level BPM.
    private weak var sectionPlayer: SongSectionPlayer?
    private let clock: any EngineClock

    public private(set) var setlist: Setlist?
    public private(set) var currentIndex: Int = -1
    public private(set) var isActive: Bool = false
    /// True after a `.pause`-mode advance while waiting for the user to
    /// press Play. Duration tracking is suspended in this state.
    public private(set) var isWaitingForResume: Bool = false

    /// Engine-clock time when the current song's duration timer started.
    /// Set after any count-in completes so users get "N measures of song"
    /// not "N measures of song-plus-count-in".
    private var songStartTime: TimeInterval = 0
    private var pollTask: Task<Void, Never>?
    private var lastEngineRunning: Bool = false
    /// Guards against overlapping advance calls when polling fires faster
    /// than the engine can settle.
    private var isAdvancing: Bool = false

    /// Tight enough for measure-boundary advance to fire within roughly
    /// one beat of the actual transition at any tempo. 50ms ≈ 1/3 of a
    /// beat at 400 BPM, 1/24 of a beat at 60 BPM.
    private static let pollIntervalMs: UInt64 = 50

    public init(
        engine: MetronomeEngine,
        sectionPlayer: SongSectionPlayer? = nil,
        clock: any EngineClock = SystemClock()
    ) {
        self.engine = engine
        self.sectionPlayer = sectionPlayer
        self.clock = clock
    }

    public var currentSong: Song? {
        guard let setlist, currentIndex >= 0, currentIndex < setlist.count else {
            return nil
        }
        return setlist[currentIndex]
    }

    /// Load a setlist and start playback from the given song index.
    /// No-op when the setlist is empty.
    public func play(_ setlist: Setlist, startingAt index: Int = 0) async {
        guard !setlist.isEmpty else { return }
        let safeIndex = max(0, min(index, setlist.count - 1))
        self.setlist = setlist
        self.currentIndex = safeIndex
        self.isActive = true
        self.isWaitingForResume = false
        await startCurrentSong(countInMeasures: 0)
        startPolling()
    }

    /// Stop playback and clear setlist state.
    public func stop() async {
        isActive = false
        isWaitingForResume = false
        pollTask?.cancel()
        pollTask = nil
        setlist = nil
        currentIndex = -1
        // Stop the section player too if it was driving a multi-section
        // song. Its own stop path clears the scheduler cap + engine.
        if let sectionPlayer, await sectionPlayer.isActive {
            await sectionPlayer.stop()
        } else {
            await engine?.stop()
        }
    }

    /// Manual next-song. Skips count-in (manual advance is intent-driven).
    /// Stops at end of setlist.
    public func next() async {
        guard let setlist, isActive else { return }
        let nextIdx = currentIndex + 1
        if nextIdx >= setlist.count {
            await stop()
            return
        }
        currentIndex = nextIdx
        isWaitingForResume = false
        await startCurrentSong(countInMeasures: 0)
    }

    /// Manual previous-song. No-op at start of setlist.
    public func previous() async {
        guard isActive else { return }
        let prevIdx = currentIndex - 1
        guard prevIdx >= 0 else { return }
        currentIndex = prevIdx
        isWaitingForResume = false
        await startCurrentSong(countInMeasures: 0)
    }

    // MARK: - Internal

    private func startCurrentSong(countInMeasures: Int) async {
        guard let song = currentSong else { return }
        let countIn = CountIn(rawValue: countInMeasures) ?? .off
        // Multi-section songs route through SongSectionPlayer so section
        // auto-advance works inside the setlist. The completion callback
        // signals "song finished" back here, which then advances the
        // setlist per its advanceMode. Count-in is forwarded so
        // `.countdown` advance mode prepends a prelude before section 0,
        // matching flat-song behavior.
        if song.isMultiSection, let sectionPlayer {
            await sectionPlayer.play(song, countIn: countIn) { [weak self] in
                guard let self else { return }
                await self.handleSectionsExhausted()
            }
            // Duration tracking is moot — SongSectionPlayer drives end.
            // Offset by the count-in prelude so any external time-based
            // logic (none today) reads consistently with flat songs.
            let countInDuration = Double(countInMeasures)
                * Double(song.timeSignature.numerator)
                * song.bpm.beatPeriod
            songStartTime = clock.now + countInDuration
            return
        }
        await engine?.apply(song)
        await engine?.start(countIn: countIn)
        // Track song start time AFTER any count-in completes so .seconds
        // duration measures "song time", not "song + preamble time".
        let countInDuration = Double(countInMeasures)
            * Double(song.timeSignature.numerator)
            * song.bpm.beatPeriod
        songStartTime = clock.now + countInDuration
    }

    /// Invoked by `SongSectionPlayer` (via the play() completion
    /// callback) when a multi-section song's sections naturally end.
    /// Advances the setlist per its advance mode just like a duration-
    /// based timeout would have.
    private func handleSectionsExhausted() async {
        guard let setlist, isActive else { return }
        isAdvancing = true
        await advance(mode: setlist.advanceMode)
        isAdvancing = false
        lastEngineRunning = await engine?.isRunning ?? false
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: Self.pollIntervalMs * 1_000_000)
            }
        }
    }

    /// Periodic check called by the poll task. Detects end-of-song based
    /// on the current song's `duration` and triggers `advance`. Also
    /// observes engine `isRunning` transitions to handle the
    /// `.pause`-mode resume case.
    public func tick() async {
        guard isActive, !isAdvancing else { return }

        let isRunningBefore = await engine?.isRunning ?? false
        // User pressed Play while we were waiting for resume after a
        // `.pause`-mode advance — start the duration timer now.
        if isWaitingForResume && isRunningBefore && !lastEngineRunning {
            isWaitingForResume = false
            songStartTime = clock.now
        }
        lastEngineRunning = isRunningBefore

        if isWaitingForResume { return }
        guard let setlist, let song = currentSong, let duration = song.duration
        else { return }
        // Multi-section songs end when sections exhaust, not on duration.
        // The SongSectionPlayer fires `handleSectionsExhausted` directly.
        if song.isMultiSection, sectionPlayer != nil { return }

        let shouldAdvance: Bool
        switch duration {
        case .seconds(let s):
            shouldAdvance = (clock.now - songStartTime) >= s
        case .measures(let m):
            // Detect the boundary just BEFORE the downbeat of measure `m`
            // would fire — so the now-stale song doesn't play one extra
            // beat. Only consult song clicks; count-in clicks have their
            // own measure indexing.
            guard let engine else { return }
            let upcoming = await engine.upcomingClicks(count: 1)
            guard let next = upcoming.first else { return }
            shouldAdvance = !next.isCountIn
                && next.measureIndex >= m
                && next.beatIndex == 0
                && next.subdivisionIndex == 0
        }

        if shouldAdvance {
            isAdvancing = true
            await advance(mode: setlist.advanceMode)
            isAdvancing = false
            // After advance, the engine state may have flipped (.pause
            // stopped it). Refresh `lastEngineRunning` so next tick's
            // resume-transition check sees a true false→true edge when
            // the user presses Play.
            lastEngineRunning = await engine?.isRunning ?? false
        }
    }

    private func advance(mode: SetlistAdvanceMode) async {
        guard let setlist else { return }
        let nextIdx = currentIndex + 1
        if nextIdx >= setlist.count {
            await stop()
            return
        }
        currentIndex = nextIdx

        switch mode {
        case .pause:
            // Stop the engine, load next song settings, wait for user.
            // Multi-section: apply the FIRST SECTION's materialized song
            // so the Stage hero shows section 0's tempo while waiting,
            // not the multi-section song's top-level fallback BPM.
            await engine?.stop()
            if let song = currentSong {
                if song.isMultiSection,
                   let first = song.sections?.first {
                    await engine?.apply(Self.materializeFirstSection(first, parent: song))
                } else {
                    await engine?.apply(song)
                }
            }
            isWaitingForResume = true
            songStartTime = 0
        case .countdown(let measures):
            await startCurrentSong(countInMeasures: measures)
        case .immediate:
            await startCurrentSong(countInMeasures: 0)
        }
    }

    /// Resume after a `.pause`-mode advance. Routes through the section
    /// player when the current song is multi-section so section auto-
    /// advance kicks in; otherwise just starts the engine directly.
    /// View-model `togglePlay` calls this whenever `isWaitingForResume`
    /// is true at the moment of press-Play.
    public func resumeAfterPause() async {
        guard isActive, isWaitingForResume, let song = currentSong else {
            return
        }
        isWaitingForResume = false
        songStartTime = clock.now
        if song.isMultiSection, let sectionPlayer {
            await sectionPlayer.play(song) { [weak self] in
                guard let self else { return }
                await self.handleSectionsExhausted()
            }
        } else {
            await engine?.start()
        }
        lastEngineRunning = await engine?.isRunning ?? false
    }

    /// Mirrors `SongSectionPlayer.materialize` — copies a section's
    /// per-section settings onto a single-section Song so `engine.apply`
    /// can re-use its setBPM / setTimeSig / etc. chain. Static to avoid
    /// tangling lifetimes; no parent-song mutation.
    private static func materializeFirstSection(_ section: SongSection, parent: Song) -> Song {
        return Song(
            id: parent.id,
            title: parent.title,
            bpm: section.bpm,
            timeSignature: section.timeSignature,
            subdivision: section.subdivision,
            accentPattern: section.accentPattern,
            soundPreset: section.soundPreset ?? parent.soundPreset,
            notes: parent.notes,
            duration: nil,
            automation: nil,
            sections: nil
        ) ?? parent
    }
}
