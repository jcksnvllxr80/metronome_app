import Foundation

/// Coordinates section-by-section playback of a multi-section song
/// (spec §7.3). Mirrors `SetlistPlayer`'s shape: actor-isolated,
/// driven by a 100 ms poll task, advances on measure boundaries.
///
/// Lifecycle:
/// - `play(song:)` applies the first section to the engine, starts
///   audio, and begins polling.
/// - Each tick checks the engine's upcoming click. If we're about to
///   cross into measure `measureCount` of the current section, we
///   apply the next section's state (via a synthesized single-section
///   Song handed to `engine.apply`). The engine re-anchors the schedule
///   at `clock.now`, so the new section's measure indexing starts at 0.
/// - When the final section's last measure is reached, we stop the
///   engine and clear local state.
///
/// Mid-section user nudges (BPM ±, time-sig change) flow through to
/// the engine and override the section's settings until the next
/// section advance replaces them. We do not write changes back to
/// `Song.sections` — sections are read-only during playback.
public actor SongSectionPlayer {
    private weak var engineRef: MetronomeEngine?
    public private(set) var song: Song?
    public private(set) var currentIndex: Int = -1
    /// Zero-based count of completed passes through the current
    /// section. When this hits `section.repeatCount - 1` AND another
    /// measure-boundary fires, the player advances to the next
    /// section instead of looping again.
    public private(set) var currentRepetition: Int = 0
    public private(set) var isActive: Bool = false
    /// True after a section with `endAction == .daCapoAlFine` finishes —
    /// playback has jumped back to section 0 and is now scanning for the
    /// next section marked `isFine`, which will be the stopping point.
    /// Spec §7.3.
    public private(set) var isAlFineMode: Bool = false
    private var pollTask: Task<Void, Never>?
    private var isAdvancing: Bool = false

    public init(engine: MetronomeEngine) {
        self.engineRef = engine
    }

    /// The currently-playing section, or nil before `play` / after `stop`.
    public var currentSection: SongSection? {
        guard let song,
              let sections = song.sections,
              currentIndex >= 0,
              currentIndex < sections.count
        else { return nil }
        return sections[currentIndex]
    }

    public var totalSections: Int {
        song?.sections?.count ?? 0
    }

    /// Start playback from the first section. Engine is started here so
    /// callers don't have to remember the order (player first, then
    /// engine.start). No-op if the song isn't multi-section.
    public func play(_ song: Song, startingAt index: Int = 0) async {
        guard song.isMultiSection,
              let sections = song.sections,
              !sections.isEmpty,
              let engine = engineRef
        else { return }
        let safeIndex = max(0, min(index, sections.count - 1))
        self.song = song
        self.currentIndex = safeIndex
        self.currentRepetition = 0
        self.isAlFineMode = false
        self.isActive = true
        let materialized = Self.materialize(section: sections[safeIndex], parentSong: song)
        await engine.apply(materialized)
        await engine.start()
        startPolling()
    }

    /// Stop section playback. Stops the engine + clears local state.
    public func stop() async {
        isActive = false
        currentIndex = -1
        currentRepetition = 0
        isAlFineMode = false
        pollTask?.cancel()
        pollTask = nil
        if let engine = engineRef {
            await engine.stop()
        }
        song = nil
    }

    /// Manual jump to the next section (skipping the remainder of the
    /// current section's measures). End-of-list stops playback.
    public func next() async {
        guard isActive else { return }
        await advanceToNextSection()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    /// Periodic boundary check. Detects "we're about to start measure
    /// `measureCount` of the current section" and advances. Public for
    /// test access — the running app drives it via the poll task.
    public func tick() async {
        guard isActive, !isAdvancing,
              let engine = engineRef,
              let section = currentSection
        else { return }
        let upcoming = await engine.upcomingClicks(count: 1)
        guard let next = upcoming.first else { return }
        // Boundary detection mirrors `SetlistPlayer.tick` — wait until
        // we're at the downbeat that WOULD have been measure
        // `measureCount` (zero-indexed: measure indices 0..<measureCount
        // are in-section; index `measureCount` is past the section).
        // Count-in clicks have their own measure indexing; ignore them.
        let atBoundary = !next.isCountIn
            && next.measureIndex >= section.measureCount
            && next.beatIndex == 0
            && next.subdivisionIndex == 0
        if atBoundary {
            isAdvancing = true
            // Decide: repeat the same section, jump (D.C. al fine),
            // stop, or advance to the next?
            if currentRepetition + 1 < section.repeatCount {
                currentRepetition += 1
                await repeatCurrentSection()
            } else if isAlFineMode && section.isFine {
                // Spec §7.3: in al-fine mode, the first Fine-marked
                // section ends the song.
                await stop()
            } else {
                switch section.endAction {
                case .stop:
                    await stop()
                case .daCapoAlFine:
                    await jumpToDaCapoAlFine()
                case .continue:
                    await advanceToNextSection()
                }
            }
            isAdvancing = false
        }
    }

    /// Re-apply the current section's settings so engine.schedule
    /// re-anchors at clock.now and measure counting restarts from 0.
    /// Sound preset / accent pattern / BPM / meter all stay the same —
    /// the engine just rebuilds its schedule.
    private func repeatCurrentSection() async {
        guard let song,
              let sections = song.sections,
              currentIndex >= 0,
              currentIndex < sections.count,
              let engine = engineRef
        else { return }
        let materialized = Self.materialize(section: sections[currentIndex], parentSong: song)
        await engine.apply(materialized)
    }

    private func advanceToNextSection() async {
        guard let song,
              let sections = song.sections,
              let engine = engineRef
        else { return }
        let nextIdx = currentIndex + 1
        if nextIdx >= sections.count {
            await stop()
            return
        }
        currentIndex = nextIdx
        currentRepetition = 0
        let materialized = Self.materialize(section: sections[nextIdx], parentSong: song)
        await engine.apply(materialized)
    }

    /// D.C. al Fine jump: go back to section 0, leave in al-fine mode
    /// so the next Fine-marked section ends the song. Repetition
    /// counter resets so the head-section's repeatCount plays out
    /// again on the second pass.
    private func jumpToDaCapoAlFine() async {
        guard let song,
              let sections = song.sections,
              !sections.isEmpty,
              let engine = engineRef
        else { return }
        currentIndex = 0
        currentRepetition = 0
        isAlFineMode = true
        let materialized = Self.materialize(section: sections[0], parentSong: song)
        await engine.apply(materialized)
    }

    /// Synthesize a single-section Song from a SongSection + its parent
    /// so `engine.apply(_:)` can reuse its existing setBPM/setTimeSig/
    /// setSubdivision/setAccentPattern/setSoundPreset chain. The
    /// returned Song's `sections` is forced to nil so re-applying
    /// doesn't recursively re-engage section playback.
    private static func materialize(section: SongSection, parentSong: Song) -> Song {
        return Song(
            id: parentSong.id,
            title: parentSong.title,
            bpm: section.bpm,
            timeSignature: section.timeSignature,
            subdivision: section.subdivision,
            accentPattern: section.accentPattern,
            soundPreset: section.soundPreset ?? parentSong.soundPreset,
            notes: parentSong.notes,
            duration: nil,
            automation: nil,
            sections: nil
        ) ?? parentSong
    }
}
