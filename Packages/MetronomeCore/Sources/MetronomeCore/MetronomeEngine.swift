import Foundation

/// Central engine class per spec §17 / CLAUDE.md Architecture.
///
/// Owns the mutable state (BPM, time signature, subdivision, accent pattern,
/// settings, running flag) and the attached `AudioScheduler`. Runs on its
/// own actor isolation. Explicitly NOT `@MainActor` so the audio scheduler
/// doesn't contend with UI work.
///
/// The scheduling math lives in `ClickSchedule`, which is pure and testable
/// with `FakeClock`. Audio output goes through `AudioScheduler` (sub-commit
/// B onward). When no scheduler is attached, the engine is fully functional
/// in silent mode — the visual pulse still drives off `upcomingClicks(count:)`.
public actor MetronomeEngine {
    private let clock: any EngineClock

    public private(set) var bpm: BPM
    public private(set) var timeSignature: TimeSignature
    public private(set) var subdivision: Subdivision
    public private(set) var accentPattern: AccentPattern?
    public private(set) var settings: EngineSettings
    public private(set) var isRunning: Bool = false
    /// `true` when the engine was paused by an audio-session interruption
    /// or route change and is waiting on `resume()`. Mutually exclusive with
    /// `isRunning`. Set back to `false` by `stop()` (full reset) or by
    /// `resume()` (returns to running).
    public private(set) var isPaused: Bool = false
    public private(set) var schedule: ClickSchedule?

    /// Audio output sink. `nil` when running silently (engine math still
    /// works; the Stage UI's visual pulse still pulses).
    public private(set) var scheduler: AudioScheduler?

    /// MIDI Clock output sink. `nil` when not attached (no CoreMIDI
    /// available, or app target didn't construct one). Optional like
    /// the audio scheduler — engine works without it.
    public private(set) var midiScheduler: MIDIScheduler?

    /// MIDI Clock input source (slave mode). When attached AND enabled
    /// in settings, incoming Clock/Start/Stop drives engine state. The
    /// engine doesn't need to actively call into it — the receiver
    /// pushes events; we keep a reference so the lifecycle is owned
    /// somewhere and the hot-toggle in setSettings can find it.
    public private(set) var midiReceiver: MIDIReceiver?

    /// Haptic feedback sink (spec §9). `nil` when not attached or when
    /// the device doesn't support haptics. The scheduler reads
    /// `settings.hapticMode` each refill, so mode toggling takes
    /// effect within ~50 ms — no engine restart needed.
    public private(set) var hapticScheduler: HapticScheduler?

    /// Sound preset string from the currently-loaded `Song`. Set by
    /// `apply(_:)`, cleared by `stop()`. The audio scheduler resolves this
    /// to a `ClickSound` at refill time; when it's `nil` or unrecognized,
    /// the scheduler falls back to `settings.clickSound`. Survives BPM /
    /// time-sig / subdivision tweaks because the sound choice is metadata
    /// about the song, not about the tempo.
    public private(set) var currentSoundPreset: String?

    /// Active tempo ramp (spec §6.3). Set by `apply(_:Song)` or
    /// `setAutomation(_:)`. Cleared by `stop()` and by any tempo edit
    /// (setBPM dropping the user mid-ramp would be confusing). Re-anchors
    /// the schedule on change while running.
    public private(set) var automation: TempoAutomation?

    /// Per-session random seed for the spec §6.4 "random mute" mode. Set
    /// at `start()` so each practice session gets a different mute
    /// pattern; cleared at `stop()`. The audio scheduler hashes
    /// (measureIndex, beatIndex, seed) to decide whether to mute a beat,
    /// which means all subdivision clicks of a muted beat share the
    /// decision — the whole beat goes silent, not just the main click.
    public private(set) var randomMuteSeed: UInt64 = 0

    public init(
        clock: any EngineClock = SystemClock(),
        bpm: BPM = BPM(120),
        timeSignature: TimeSignature = .fourFour,
        subdivision: Subdivision = .none,
        accentPattern: AccentPattern? = nil,
        settings: EngineSettings = EngineSettings()
    ) {
        self.clock = clock
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.subdivision = subdivision
        self.settings = settings
        if let pattern = accentPattern, pattern.timeSignature == timeSignature {
            self.accentPattern = pattern
        } else {
            self.accentPattern = nil
        }
    }

    /// Anchor a new click sequence at `clock.now` and mark running. When an
    /// audio scheduler is attached, also starts audio playback.
    ///
    /// `countIn` overrides `settings.countIn` for this start. When `nil`,
    /// the engine uses its persisted setting.
    public func start(countIn: CountIn? = nil) async {
        let effective = countIn ?? settings.countIn
        // Fresh random-mute seed per practice session so consecutive
        // playthroughs don't share the same muted-beat pattern.
        randomMuteSeed = UInt64.random(in: .min ... .max)
        rebuildSchedule(countIn: effective, leadIn: Self.startupLeadInSeconds)
        isRunning = true
        isPaused = false
        if let scheduler {
            await scheduler.start(engine: self)
        }
        if let midiScheduler {
            await midiScheduler.setEnabled(settings.midiClockEnabled)
            await midiScheduler.start(engine: self)
        }
        if let hapticScheduler {
            await hapticScheduler.start(engine: self)
        }
    }

    /// Stop emitting clicks. The schedule is cleared; audio (if attached)
    /// is torn down. The current sound preset and automation are cleared so
    /// the next engine.start() reverts to the global setting until a Song
    /// is applied.
    public func stop() async {
        isRunning = false
        isPaused = false
        schedule = nil
        currentSoundPreset = nil
        automation = nil
        if let scheduler {
            await scheduler.stop()
        }
        if let midiScheduler {
            await midiScheduler.stop()
        }
        if let hapticScheduler {
            await hapticScheduler.stop()
        }
    }

    /// Pause playback without tearing down the audio engine. Used for
    /// audio-session interruptions (phone calls, Siri) and route changes
    /// (headphone unplug). The schedule is preserved so `resume()` can
    /// re-anchor at `clock.now` without losing user intent. No-op when
    /// not running.
    public func pause() async {
        guard isRunning else { return }
        isRunning = false
        isPaused = true
        // Schedule stays — resume() will re-anchor it.
        if let scheduler {
            await scheduler.pause()
        }
        // For MIDI we send Stop on pause; resume sends Start again.
        // Continuing across a phone-call interruption with a half-second
        // gap of Clock pulses confuses many DAWs more than a clean
        // Stop/Start cycle does.
        if let midiScheduler {
            await midiScheduler.stop()
        }
        if let hapticScheduler {
            await hapticScheduler.stop()
        }
    }

    /// Resume after a `pause()`. Re-anchors the click sequence at `clock.now`
    /// (no count-in — this is a continuation, not a new start). No-op when
    /// not paused. Called by the audio session coordinator when an
    /// interruption ends with `.shouldResume` AND
    /// `settings.autoResumeAfterInterruption` is true, OR manually by the
    /// user pressing Play.
    public func resume() async {
        guard isPaused else { return }
        // Same lead-in story as start(): the audio scheduler is being
        // brought back up from pause() which stopped the player node;
        // the first scheduleBuffer call after resume races the audio
        // engine's wake-up the same way an initial start does.
        rebuildSchedule(countIn: .off, leadIn: Self.startupLeadInSeconds)
        isRunning = true
        isPaused = false
        if let scheduler {
            await scheduler.resume(engine: self)
        }
        if let midiScheduler {
            await midiScheduler.setEnabled(settings.midiClockEnabled)
            await midiScheduler.start(engine: self)
        }
        if let hapticScheduler {
            await hapticScheduler.start(engine: self)
        }
    }

    /// Change tempo. Re-anchors the click sequence at `clock.now` when running.
    /// Clears any active automation — a manual BPM nudge mid-ramp is the
    /// user telling us to abandon the ramp.
    public func setBPM(_ newBPM: BPM) {
        bpm = newBPM
        automation = nil
        reanchorIfRunning()
    }

    /// Set or clear the active tempo automation. When `auto` is non-nil,
    /// `bpm` is forced to `auto.startBPM` so the schedule's precondition
    /// holds. Re-anchors the schedule on running change.
    public func setAutomation(_ auto: TempoAutomation?) {
        automation = auto
        if let auto {
            bpm = auto.startBPM
        }
        reanchorIfRunning()
    }

    /// Change time signature. If the active accent pattern was scoped to the
    /// old time signature, it is cleared (per spec §3.2 / CLAUDE.md).
    public func setTimeSignature(_ newTS: TimeSignature) {
        timeSignature = newTS
        if let pattern = accentPattern, pattern.timeSignature != newTS {
            accentPattern = nil
        }
        reanchorIfRunning()
    }

    public func setSubdivision(_ newSub: Subdivision) {
        subdivision = newSub
        reanchorIfRunning()
    }

    /// Set or clear the accent pattern. Returns `true` if accepted; `false`
    /// if the pattern's time signature doesn't match the engine's current
    /// time signature. Passing `nil` always succeeds.
    @discardableResult
    public func setAccentPattern(_ pattern: AccentPattern?) -> Bool {
        if let pattern, pattern.timeSignature != timeSignature {
            return false
        }
        accentPattern = pattern
        reanchorIfRunning()
        return true
    }

    /// Replace the engine's settings wholesale.
    public func setSettings(_ newSettings: EngineSettings) {
        let oldMidi = settings.midiClockEnabled
        let oldMidiRx = settings.midiClockReceiveEnabled
        settings = newSettings
        // Hot-apply midiClockEnabled so the user toggling it in the
        // Settings sheet takes effect immediately (no need to stop and
        // restart the engine).
        if let midiScheduler, oldMidi != newSettings.midiClockEnabled {
            Task { [midiScheduler, newSettings, isRunning, isPaused] in
                await midiScheduler.setEnabled(newSettings.midiClockEnabled)
                if newSettings.midiClockEnabled && isRunning {
                    await midiScheduler.start(engine: self)
                } else if !newSettings.midiClockEnabled {
                    await midiScheduler.stop()
                }
                _ = isPaused // silence unused-capture warning
            }
        }
        // Hot-apply receive toggle. When enabled, the receiver starts
        // connecting to external sources; when disabled, it disconnects
        // and drops in-flight tick state.
        if let midiReceiver, oldMidiRx != newSettings.midiClockReceiveEnabled {
            Task { [midiReceiver, newSettings] in
                await midiReceiver.setEnabled(newSettings.midiClockReceiveEnabled)
            }
        }
    }

    /// Set or clear the active song's sound preset. Called by
    /// `apply(_:Song)`; the audio scheduler reads this each refill and
    /// uses it (when it resolves to a known `ClickSound`) instead of
    /// `settings.clickSound`. Pass `nil` to revert to the global default.
    public func setSoundPreset(_ preset: String?) {
        currentSoundPreset = preset
    }

    /// Attach an `AudioScheduler` for audio output. The app target builds
    /// the scheduler (which owns `AVAudioEngine`) and hands it in. Pass
    /// `nil` to detach (silent mode).
    public func attach(scheduler: AudioScheduler?) {
        self.scheduler = scheduler
    }

    /// Attach a `MIDIScheduler` for MIDI Clock output. The app target
    /// constructs it (may fail to allocate CoreMIDI resources, returning
    /// nil). Pass `nil` to detach.
    public func attach(midi: MIDIScheduler?) {
        self.midiScheduler = midi
    }

    /// Attach a `MIDIReceiver` for slave-mode tempo following. The
    /// receiver pushes events into the engine; the engine doesn't pull.
    public func attach(midiReceiver: MIDIReceiver?) {
        self.midiReceiver = midiReceiver
    }

    /// Attach a `HapticScheduler` for haptic feedback. The scheduler
    /// reads `settings.hapticMode` each refill, so toggling mode on a
    /// running engine takes effect immediately. Pass `nil` to detach.
    public func attach(haptic: HapticScheduler?) {
        self.hapticScheduler = haptic
    }

    /// Apply a song's state AND reset the audio scheduler in a single
    /// atomic operation. Used by `SongSectionPlayer` for section
    /// transitions where the standard `apply()` path was producing
    /// timing problems because each of its 5 internal setters
    /// dispatched a separate `scheduleReset` Task on the audio
    /// scheduler, racing with the explicit cap update the section
    /// player needed to do afterwards.
    ///
    /// This method temporarily detaches the audio scheduler while
    /// running the standard `apply()` chain — so the 5 reanchor
    /// Tasks don't fire on it — then re-attaches and does ONE
    /// explicit `scheduleResetWithCap` call with the new section's
    /// boundary. MIDI and haptic schedulers stay attached and get
    /// their normal reanchor Tasks (they need them).
    public func applyForSectionTransition(_ song: Song, sectionMeasureCount: Int) async {
        let savedScheduler = self.scheduler
        self.scheduler = nil
        apply(song)
        self.scheduler = savedScheduler

        guard isRunning,
              let scheduler = savedScheduler,
              let schedule = self.schedule
        else { return }

        let songFirstClickIndex = schedule.countInClicks
        let boundaryClickIndex = songFirstClickIndex + sectionMeasureCount * schedule.clicksPerMeasure
        let boundaryTime = schedule.click(at: boundaryClickIndex).time
        await scheduler.scheduleResetWithCap(boundaryTime)
    }

    /// Next `count` clicks starting at or after `clock.now`. Returns `[]`
    /// when the engine is stopped. The UI uses this to drive the visual
    /// pulse + active beat indicator.
    public func upcomingClicks(count: Int) -> [Click] {
        guard isRunning, let schedule else { return [] }
        return schedule.clicks(from: clock.now, count: count)
    }

    /// Clicks with `time > after`, up to `count`. Used by `AudioScheduler`
    /// to drive its refill loop — passing the last-scheduled click's time
    /// prevents re-scheduling clicks that are already in the player node's
    /// queue. Returns `[]` when stopped.
    public func clicks(after: TimeInterval, count: Int) -> [Click] {
        guard isRunning, let schedule else { return [] }
        // `firstClickIndex(atOrAfter:)` is inclusive; offset by a tiny
        // epsilon so a click at exactly `after` isn't returned again.
        let strict = after + 1e-9
        let startIdx = schedule.firstClickIndex(atOrAfter: strict)
        return (0..<count).map { schedule.click(at: startIdx + $0) }
    }

    // MARK: - Private

    /// Lead-in applied to the schedule anchor on a cold `start()` or
    /// `resume()`. The audio session activation + AVAudioEngine startup
    /// take non-trivial time to reach `scheduleBuffer(at:)`; if the
    /// first click's hostTime is behind that wall-clock, the player
    /// node drops it — and the audible accent ends up on what feels
    /// like the wrong beat. 250 ms covers the typical cold-launch
    /// window (which can run higher than 100 ms on a first activation
    /// since the audio subsystem is being initialized for the first
    /// time). Tradeoff: a slight delay between Play tap and first click;
    /// preferable to a missing downbeat.
    public static let startupLeadInSeconds: TimeInterval = 0.250

    /// Lead-in applied when re-anchoring the schedule mid-playback (BPM
    /// nudge, time-signature change, subdivision change). The audio
    /// engine is already running, so the cold-start latency doesn't
    /// apply — but the player node still needs a moment to recover
    /// from `playerNode.reset()` and pick up newly-scheduled buffers.
    /// 60 ms is short enough not to feel laggy on a nudge, long enough
    /// to cover the reset/refill round-trip.
    public static let reanchorLeadInSeconds: TimeInterval = 0.060

    private func rebuildSchedule(countIn: CountIn = .off, leadIn: TimeInterval = 0) {
        schedule = ClickSchedule(
            bpm: bpm,
            timeSignature: timeSignature,
            subdivision: subdivision,
            startTime: clock.now + leadIn,
            accentPattern: accentPattern,
            countInMeasures: countIn.measures,
            automation: automation
        )
    }

    private func reanchorIfRunning() {
        guard isRunning else { return }
        // Mid-run re-anchors never re-trigger count-in. The small
        // lead-in gives the audio path time to recover from the
        // scheduler's queue flush (see AudioScheduler.scheduleReset)
        // without dropping the first new-tempo click.
        rebuildSchedule(countIn: .off, leadIn: Self.reanchorLeadInSeconds)
        // Notify the scheduler so it can flush its buffered queue and
        // refill from the new schedule. Fire-and-forget: capture the
        // scheduler reference, not self.
        if let scheduler {
            Task { [scheduler] in
                await scheduler.scheduleReset()
            }
        }
        // MIDI parallel: drop the tick counter so the refill loop
        // re-anchors against the new schedule.startTime + new BPM.
        if let midiScheduler {
            Task { [midiScheduler] in
                await midiScheduler.scheduleReset()
            }
        }
        if let hapticScheduler {
            Task { [hapticScheduler] in
                await hapticScheduler.scheduleReset()
            }
        }
    }
}
