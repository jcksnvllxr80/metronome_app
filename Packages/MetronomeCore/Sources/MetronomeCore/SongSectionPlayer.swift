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
    /// Local clock used for time-based boundary detection. Same backing
    /// source (mach_absolute_time) as the engine's clock, so the times
    /// we compare against `schedule.startTime` are in the same timebase.
    /// Injectable so tests can drive `FakeClock`-synchronized advance.
    private let clock: any EngineClock
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
    /// Optional handler invoked when the song's sections naturally
    /// exhaust (continue-past-last, .stop endAction, or al-fine hits a
    /// Fine-marked section). Set by `SetlistPlayer` so it can advance
    /// to the next song without the section player stopping the engine.
    /// When nil (standalone playback), natural end stops the engine.
    private var onSectionsExhausted: (@Sendable () async -> Void)?

    public init(engine: MetronomeEngine, clock: any EngineClock = SystemClock()) {
        self.engineRef = engine
        self.clock = clock
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
    ///
    /// `onSectionsExhausted` is invoked when the song's sections end
    /// naturally — used by `SetlistPlayer` to chain into the next song
    /// without the section player tearing down the engine. When the
    /// callback is set, natural-end paths skip `engine.stop()` and the
    /// caller is responsible for the next action.
    public func play(
        _ song: Song,
        startingAt index: Int = 0,
        onSectionsExhausted: (@Sendable () async -> Void)? = nil
    ) async {
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
        self.onSectionsExhausted = onSectionsExhausted
        let firstSection = sections[safeIndex]
        let materialized = Self.materialize(section: firstSection, parentSong: song)
        // First-section start: standard apply + start the engine. The
        // applyForSectionTransition path is for AFTER engine.start has
        // already been called (mid-playback transitions).
        await engine.apply(materialized)
        await engine.start()
        // Set the initial section's boundary cap on the audio scheduler.
        if let scheduler = await engine.scheduler,
           let schedule = await engine.schedule {
            let songFirstClickIndex = schedule.countInClicks
            let boundaryClickIndex = songFirstClickIndex + firstSection.measureCount * schedule.clicksPerMeasure
            let boundaryTime = schedule.click(at: boundaryClickIndex).time
            await scheduler.scheduleResetWithCap(boundaryTime)
        }
        startPolling()
    }

    /// Stop section playback. Stops the engine + clears local state.
    /// Manual stop path — discards any exhausted-callback so the caller
    /// (typically the user pressing Stop) is treated as final.
    public func stop() async {
        await teardown(stopEngine: true)
    }

    /// Natural end-of-song path. If a completion callback was registered
    /// (setlist playback), invoke it AFTER clearing local state, leaving
    /// the engine running so the caller can transition into the next
    /// song. Otherwise, fall through to the same teardown as `stop()`
    /// (stops the engine — standalone playback).
    private func endNaturally() async {
        if let callback = onSectionsExhausted {
            await teardown(stopEngine: false)
            await callback()
        } else {
            await teardown(stopEngine: true)
        }
    }

    private func teardown(stopEngine: Bool) async {
        isActive = false
        currentIndex = -1
        currentRepetition = 0
        isAlFineMode = false
        onSectionsExhausted = nil
        pollTask?.cancel()
        pollTask = nil
        if let engine = engineRef {
            // Clear the scheduling cap so any later non-section play
            // doesn't inherit it. The scheduler instance persists even
            // when the engine is stopped, so the stale cap would leak
            // through.
            if let scheduler = await engine.scheduler {
                await scheduler.setSchedulingEndTime(nil)
            }
            if stopEngine {
                await engine.stop()
            }
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
        // Compute the wall-clock time at which the section's natural
        // boundary lands (the would-be downbeat of measure
        // `measureCount`, past the last in-section measure). Detect by
        // time rather than by "next click is the boundary click" —
        // the lookahead-based check fired as soon as the upcoming
        // click WAS the boundary, which could be most of a click
        // period away, causing the transition to land early and cut
        // off the end of the current section.
        guard let schedule = await engine.schedule else { return }
        let songFirstClickIndex = schedule.countInClicks
        let boundaryClickIndex = songFirstClickIndex + section.measureCount * schedule.clicksPerMeasure
        let boundaryTime = schedule.click(at: boundaryClickIndex).time
        // Trigger the advance a tick before the boundary so the new
        // section's first click — which lands at clock.now + reanchor
        // lead-in — fires AT the boundary time, not after it. The
        // 100ms poll interval makes this a "fire on the first tick
        // past advanceTime" — the worst-case is one poll interval
        // of overshoot.
        let advanceTime = boundaryTime - MetronomeEngine.reanchorLeadInSeconds
        let atBoundary = clock.now >= advanceTime
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
                await endNaturally()
            } else {
                switch section.endAction {
                case .stop:
                    await endNaturally()
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
        let section = sections[currentIndex]
        let materialized = Self.materialize(section: section, parentSong: song)
        await engine.applyForSectionTransition(materialized, sectionMeasureCount: section.measureCount)
    }

    private func advanceToNextSection() async {
        guard let song,
              let sections = song.sections,
              let engine = engineRef
        else { return }
        let nextIdx = currentIndex + 1
        if nextIdx >= sections.count {
            await endNaturally()
            return
        }
        currentIndex = nextIdx
        currentRepetition = 0
        let nextSection = sections[nextIdx]
        let materialized = Self.materialize(section: nextSection, parentSong: song)
        await engine.applyForSectionTransition(materialized, sectionMeasureCount: nextSection.measureCount)
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
        let firstSection = sections[0]
        let materialized = Self.materialize(section: firstSection, parentSong: song)
        await engine.applyForSectionTransition(materialized, sectionMeasureCount: firstSection.measureCount)
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
