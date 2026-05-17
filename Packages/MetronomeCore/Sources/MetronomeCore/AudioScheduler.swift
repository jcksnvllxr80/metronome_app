import Foundation
import AVFoundation

#if canImport(UIKit)
import AVFAudio
#endif

/// Owns the `AVAudioEngine` and schedules click buffers ahead of the engine
/// clock. **Sub-commit B: first audible output.** Maintains a 4-click
/// lookahead via a refill loop. The engine pushes "schedule changed" events
/// (BPM / time-sig / accent edits) via `scheduleReset()`; the scheduler
/// flushes pending buffers and re-fills from the new schedule's `clock.now`.
///
/// Sub-commit C will: handle `AVAudioSession` interruptions + route changes,
/// adopt the Phase 1 sound library (replace `ClickBufferGenerator` with
/// real samples), make lookahead BPM-adaptive, and add `pause`/`resume`.
public actor AudioScheduler {
    /// Fraction of a second the refill loop sleeps between passes. 50 ms is
    /// well under one click period at the max tempo (60/400 = 150 ms), so
    /// the lookahead queue never drains.
    private static let refillIntervalMs: UInt64 = 50

    /// Minimum number of clicks in the player node's pre-scheduled queue
    /// (spec §1.2 floor of 4). Adaptive policy: lookahead = max(4,
    /// ceil(minLookaheadSeconds / clickPeriod)) so at 400 BPM (period
    /// 150 ms) we queue ~4 clicks worth of audio (~600 ms), and at slow
    /// tempos we never queue MORE than necessary — keeps tempo-change
    /// latency bounded.
    private static let minLookaheadClicks: Int = 4
    private static let minLookaheadSeconds: TimeInterval = 0.5
    /// Upper bound on clicks queued ahead. Stops pathological tempo +
    /// subdivision combinations (e.g., 400 BPM custom-9 → 31 clicks)
    /// from continuing to grow into territory that doesn't help latency
    /// but does balloon recovery cost on schedule-reset.
    private static let maxLookaheadClicks: Int = 48

    public let avEngine: AVAudioEngine
    public let playerNode: AVAudioPlayerNode
    /// Secondary player node for the polyrhythm stream (spec §2.4).
    /// Owns its own volume so the polyrhythm config's volume slider is
    /// applied independent of the primary mix. Receives buffers built
    /// from the polyrhythm's configured sound at `.accent` level so
    /// each pulse reads clearly against the primary stream.
    public let polyPlayerNode: AVAudioPlayerNode
    public let format: AVAudioFormat
    /// User-imported sound registry (spec §4.2). Owns a per-sound
    /// per-accent buffer cache built from files in the app sandbox.
    /// Public so the app target's store layer can push fresh snapshots
    /// as the user adds / removes / re-trims imports. nil-safe — if
    /// no app-target store attaches one, the audio path simply skips
    /// any `user:UUID` preset key and falls through to the built-in
    /// sound at the next level of resolution.
    public let userSoundRegistry: UserSoundRegistry

    private let clock = SystemClock()
    /// Hard upper bound on the click times we'll schedule. Set by
    /// `SongSectionPlayer` to the current section's boundary time so
    /// the OLD section's "next-measure downbeat" — which lives at the
    /// boundary's hostTime — never enters the player node's queue.
    /// Without this cap, that click and the NEW section's first click
    /// both fire at boundaryTime, producing the "two downbeats"
    /// device QA reported. `nil` means "no cap" (the standalone
    /// non-section playback path).
    private var schedulingEndTime: TimeInterval?
    /// Pre-rendered buffers keyed by (sound × accent × pitch). 4 sounds ×
    /// 5 accents × 3 pitches = 60 buffers (~450 KB total at 48 kHz).
    /// Pre-computing at init means switching ClickSound or per-beat
    /// pitch/sound overrides shows up audibly within one refill pass
    /// (~50 ms) — no buffer generation on the audio path.
    private struct BufferKey: Hashable {
        let sound: ClickSound
        let accent: AccentLevel
        let pitch: PitchShift
    }
    private var clickBuffers: [BufferKey: AVAudioPCMBuffer] = [:]

    /// Voice-count buffers keyed by (beatIndex 0–8 × accent). Higher beat
    /// indices clamp to 8 (the synthesized pitch table saturates beyond
    /// that — distinguishing beat 12 vs beat 13 vocally is past human
    /// comprehension anyway).
    private struct VoiceBufferKey: Hashable {
        let beatIndex: Int
        let accent: AccentLevel
    }
    private var voiceBuffers: [VoiceBufferKey: AVAudioPCMBuffer] = [:]
    private static let voicePitchBuckets: Int = 9
    private weak var engineRef: MetronomeEngine?
    private var refillTask: Task<Void, Never>?
    /// The `EngineClock` time of the most recently scheduled click. Used
    /// to ask the engine only for clicks AFTER this point — prevents
    /// re-scheduling the same click on every refill pass.
    private var lastScheduledTime: TimeInterval = -.infinity
    /// Same as `lastScheduledTime` but for the polyrhythm stream.
    /// Separate counter because the two streams are at different
    /// periods — primary refills don't tell us anything about which
    /// poly pulses have already been queued.
    private var lastPolyScheduledTime: TimeInterval = -.infinity

    public init() {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let polyNode = AVAudioPlayerNode()
        engine.attach(node)
        engine.attach(polyNode)
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        engine.connect(polyNode, to: engine.mainMixerNode, format: fmt)
        self.avEngine = engine
        self.playerNode = node
        self.polyPlayerNode = polyNode
        self.format = fmt
        self.userSoundRegistry = UserSoundRegistry()

        // Pre-render one buffer per (sound, accent, pitch) combo.
        for sound in ClickSound.allCases {
            for level in AccentLevel.allCases {
                for pitch in PitchShift.allCases {
                    if let buf = ClickBufferGenerator.makeBuffer(
                        format: fmt, accent: level, sound: sound, pitch: pitch
                    ) {
                        clickBuffers[BufferKey(sound: sound, accent: level, pitch: pitch)] = buf
                    }
                }
            }
        }
        // Pre-render voice-count buffers — one per (beatIndex, accent).
        for beatIdx in 0..<Self.voicePitchBuckets {
            for level in AccentLevel.allCases {
                if let buf = ClickBufferGenerator.makeVoiceTone(
                    format: fmt, beatIndex: beatIdx, accent: level
                ) {
                    voiceBuffers[VoiceBufferKey(beatIndex: beatIdx, accent: level)] = buf
                }
            }
        }
    }

    /// Activate the audio session, start the AVAudioEngine + player node,
    /// and begin the refill loop. Idempotent — calling on an already-
    /// running scheduler resets the lookahead queue.
    public func start(engine: MetronomeEngine) async {
        self.engineRef = engine
        lastScheduledTime = -.infinity
        lastPolyScheduledTime = -.infinity

        activateSession()

        if !avEngine.isRunning {
            do { try avEngine.start() }
            catch { print("AudioScheduler: avEngine.start failed: \(error)") }
        }
        if !playerNode.isPlaying {
            playerNode.play()
        }
        if !polyPlayerNode.isPlaying {
            polyPlayerNode.play()
        }

        refillTask?.cancel()
        refillTask = Task { [weak self] in
            await self?.refillLoop()
        }
    }

    /// Tear down audio output: cancel the refill task, stop the player
    /// nodes + AVAudioEngine. Buffers still queued in the player node
    /// are dropped. The `AVAudioSession` is intentionally NOT
    /// deactivated here — that's important for two reasons:
    ///
    ///   1. The volume-key bridge (spec §10.4) KVO-observes
    ///      `AVAudioSession.outputVolume`. iOS pauses that observation
    ///      when the session is inactive, so deactivating on stop
    ///      meant volume keys would fire on the first start→stop
    ///      cycle and then go silent afterwards.
    ///   2. The Now Playing slot (spec §16) sticks to the most
    ///      recent active-session app. Keeping ours active means
    ///      the lock-screen card survives a stop/start cycle and
    ///      AirPods controls keep reaching us between sessions.
    ///
    /// The OS handles session deactivation automatically on app
    /// suspension; manual deactivation is reserved for cases where
    /// we explicitly want to yield control (none of those exist on
    /// the meter-gnome path today).
    public func stop() async {
        refillTask?.cancel()
        refillTask = nil

        playerNode.stop()
        polyPlayerNode.stop()
        avEngine.stop()
        playerNode.reset()
        polyPlayerNode.reset()
        lastScheduledTime = -.infinity
        lastPolyScheduledTime = -.infinity

        engineRef = nil
    }

    /// Light teardown for interruption / route-change pauses. Cancels the
    /// refill task and stops the player node, but keeps `AVAudioEngine`
    /// running and the session active so `resume(engine:)` can pick up
    /// quickly. The engine reference is held — `resume` re-uses it.
    public func pause() async {
        refillTask?.cancel()
        refillTask = nil
        playerNode.stop()
        polyPlayerNode.stop()
        playerNode.reset()
        polyPlayerNode.reset()
        lastScheduledTime = -.infinity
        lastPolyScheduledTime = -.infinity
    }

    /// Pair to `pause()`. Re-attaches the engine reference and restarts
    /// the player node + refill loop. Faster than full `start(engine:)`
    /// because `AVAudioEngine` and the audio session stay live across
    /// the pause.
    public func resume(engine: MetronomeEngine) async {
        self.engineRef = engine
        lastScheduledTime = -.infinity
        lastPolyScheduledTime = -.infinity
        if !avEngine.isRunning {
            do { try avEngine.start() }
            catch { print("AudioScheduler: avEngine.start failed on resume: \(error)") }
        }
        playerNode.play()
        polyPlayerNode.play()
        refillTask?.cancel()
        refillTask = Task { [weak self] in
            await self?.refillLoop()
        }
    }

    /// Engine calls this when it rebuilds its schedule (BPM change, time
    /// signature change, etc.). Uses `.interrupts` on the first newly-
    /// scheduled buffer so the player node preempts the stale-tempo
    /// queue without calling `playerNode.reset()` — which had been
    /// causing an audible dropout that no amount of post-reset lead-in
    /// could fully close.
    public func scheduleReset() async {
        guard playerNode.isPlaying else { return }
        // Drop both tracking high-water marks so the refill pulls
        // clicks (primary AND polyrhythm) from the new schedule's
        // beginning. The `.interrupts` flag on the first scheduled
        // buffer of each stream tells the player nodes to abandon
        // their in-flight queues and play the new buffers instead.
        lastScheduledTime = -.infinity
        lastPolyScheduledTime = -.infinity
        await refillOnce(interruptsFirst: true)
    }

    /// Set the hard upper bound on click times this scheduler will
    /// queue. Pass `nil` to clear (standalone playback). Section
    /// playback sets this to each section's boundary so the OLD
    /// section's "next-measure downbeat" never gets queued and the
    /// NEW section's first click owns the boundary hostTime alone.
    public func setSchedulingEndTime(_ time: TimeInterval?) {
        self.schedulingEndTime = time
    }

    /// Update the cap AND trigger an immediate refill in a single
    /// actor-isolated call. Section transitions need this combined
    /// operation because if we just call `setSchedulingEndTime`
    /// separately after `engine.apply`, the 5 scheduleReset Tasks
    /// the apply chain dispatches run BEFORE our cap update — and
    /// they run with the OLD cap, which happens to equal the NEW
    /// section's first click hostTime. So they reject the new click.
    /// Result: new section's clicks never queue, tempo stays stuck
    /// at old. Doing both inside one method body bypasses the
    /// interleaving — the cap is updated first, then the refill
    /// picks it up immediately.
    public func scheduleResetWithCap(_ newCap: TimeInterval?) async {
        self.schedulingEndTime = newCap
        lastScheduledTime = -.infinity
        lastPolyScheduledTime = -.infinity
        guard playerNode.isPlaying else { return }
        await refillOnce(interruptsFirst: true)
    }

    /// Hard reset variant for cases where the existing queue contains
    /// buffers we definitely DON'T want to play — e.g. section
    /// boundaries, where the OLD section's "next-measure downbeat"
    /// click has already been scheduled at the boundary hostTime and
    /// would play alongside the NEW section's first click otherwise
    /// (producing the "two downbeats" reported on device).
    /// `.interrupts` only preempts the buffer currently rendering —
    /// future-queued buffers survive — so we call `playerNode.stop()`
    /// + `play()` to actually drop everything, then re-queue.
    public func scheduleResetWithFlush() async {
        guard playerNode.isPlaying else { return }
        playerNode.stop()
        polyPlayerNode.stop()
        playerNode.play()
        polyPlayerNode.play()
        lastScheduledTime = -.infinity
        lastPolyScheduledTime = -.infinity
        // No need for `.interrupts` — the queues are already empty.
        await refillOnce(interruptsFirst: false)
    }

    // MARK: - Refill loop

    private func refillLoop() async {
        while !Task.isCancelled {
            await refillOnce(interruptsFirst: false)
            try? await Task.sleep(nanoseconds: Self.refillIntervalMs * 1_000_000)
        }
    }

    /// `interruptsFirst` adds the `.interrupts` option to the first
    /// scheduled buffer of this pass, telling AVAudioPlayerNode to
    /// preempt any in-flight buffer playback. Used during a schedule
    /// reset (tempo / meter / subdivision change mid-playback) to make
    /// the new tempo audible immediately instead of waiting for the
    /// old queue to drain or paying the dropout cost of
    /// `playerNode.reset()`.
    private func refillOnce(interruptsFirst: Bool = false) async {
        guard let engine = engineRef else { return }
        let settings = await engine.settings
        let songPreset = await engine.currentSoundPreset
        let muteSeed = await engine.randomMuteSeed
        let lookahead = await adaptiveLookahead(for: engine)

        // Apply master volume each pass. AVAudioPlayerNode.volume is thread-
        // safe and the assignment is idempotent — keeping it here means
        // the slider's effect shows up within one refill interval (~50ms).
        playerNode.volume = Float(settings.masterVolume)

        let upcoming = await engine.clicks(after: lastScheduledTime, count: lookahead)
        let endTime = schedulingEndTime
        var didScheduleAny = false
        for click in upcoming {
            // Hard cap — don't queue clicks past the section boundary.
            // Without this, the boundary click (which belongs to the
            // NEXT section's measure 0, not this section) ends up
            // in the queue and plays alongside the new section's
            // first click after the transition.
            if let endTime = endTime, click.time >= endTime { break }
            // Mute click: still advance `lastScheduledTime` so we don't
            // re-pull it next pass, but don't schedule anything audible.
            if click.accent == .mute {
                lastScheduledTime = click.time
                continue
            }
            // Random-mute mode (spec §6.4). Count-in beats are exempt so
            // the musician always hears the lead-in. Subdivisions inherit
            // the main beat's mute decision (same hash key) so the whole
            // beat goes silent together, not just the main click.
            if !click.isCountIn,
               Self.shouldRandomlyMute(
                   measure: click.measureIndex,
                   beat: click.beatIndex,
                   seed: muteSeed,
                   percentage: settings.randomMutePercentage
               ) {
                lastScheduledTime = click.time
                continue
            }
            // Voice count override: when in .beats mode and this is a
            // main beat (not a subdivision), play a per-beat-number
            // pitched tone instead of the regular click. Subdivisions
            // fall through to the normal click path so users still
            // get rhythmic feedback between voiced beats.
            var buffer: AVAudioPCMBuffer? = nil
            if settings.voiceCountMode == .beats,
               click.subdivisionIndex == 0 {
                let bucket = min(click.beatIndex, Self.voicePitchBuckets - 1)
                buffer = voiceBuffers[VoiceBufferKey(beatIndex: bucket, accent: click.accent)]
            }
            // Sound resolution order, narrowest to broadest. At each
            // level, a `user:<UUID>` key takes the imported-sound path
            // (UserSoundRegistry); otherwise we map the string back to
            // a built-in ClickSound and look up the synth buffer.
            //   1. click.soundOverride — set per-beat in an AccentPattern
            //   2. engine.currentSoundPreset — set per-song
            //   3. settings.clickSound — global default (built-in only;
            //      Settings picker still exposes user sounds but routes
            //      them through currentSoundPreset)
            if buffer == nil, let s = click.soundOverride {
                buffer = await resolveBuffer(forKey: s, accent: click.accent, pitch: click.pitchShift)
            }
            if buffer == nil, let s = songPreset {
                buffer = await resolveBuffer(forKey: s, accent: click.accent, pitch: click.pitchShift)
            }
            if buffer == nil {
                let bufferKey = BufferKey(
                    sound: settings.clickSound,
                    accent: click.accent,
                    pitch: click.pitchShift
                )
                buffer = clickBuffers[bufferKey]
            }
            guard let buffer else { continue }
            // Apply latency calibration. Negative = fire earlier
            // (compensates for Bluetooth headphone output latency).
            // Already clamped to ±50ms by EngineSettings.init.
            let adjustedTime = click.time + settings.latencyOffsetSeconds
            let audioTime = clock.audioTime(forEngineTime: adjustedTime)
            // First buffer of a reset pass uses `.interrupts` so it
            // preempts whatever the player node was about to render —
            // that's how we drop the stale-tempo queue without calling
            // `playerNode.reset()` (which had its own dropout problem).
            let options: AVAudioPlayerNodeBufferOptions =
                (interruptsFirst && !didScheduleAny) ? [.interrupts] : []
            // Explicit `completionHandler: nil` selects the legacy sync
            // overload — the 2-arg form binds to an async variant in
            // recent SDKs that we don't want (awaiting it would block
            // the refill loop until the buffer finishes playing).
            playerNode.scheduleBuffer(buffer, at: audioTime, options: options, completionHandler: nil)
            lastScheduledTime = click.time
            didScheduleAny = true
        }

        // Polyrhythm stream (spec §2.4). Independent player node so the
        // poly volume slider doesn't fight the primary mix. Skip entirely
        // when polyrhythm is off — saves a refill call into the engine.
        if let poly = settings.polyrhythm {
            polyPlayerNode.volume = Float(settings.masterVolume * poly.volume)
            let upcomingPoly = await engine.polyClicks(
                after: lastPolyScheduledTime,
                count: lookahead
            )
            var didSchedulePolyAny = false
            for pc in upcomingPoly {
                if let endTime = endTime, pc.time >= endTime { break }
                let bufferKey = BufferKey(
                    sound: pc.sound,
                    accent: .accent,
                    pitch: .unison
                )
                guard let buffer = clickBuffers[bufferKey] else { continue }
                let adjustedTime = pc.time + settings.latencyOffsetSeconds
                let audioTime = clock.audioTime(forEngineTime: adjustedTime)
                let options: AVAudioPlayerNodeBufferOptions =
                    (interruptsFirst && !didSchedulePolyAny) ? [.interrupts] : []
                polyPlayerNode.scheduleBuffer(buffer, at: audioTime, options: options, completionHandler: nil)
                lastPolyScheduledTime = pc.time
                didSchedulePolyAny = true
            }
        } else {
            // Polyrhythm disabled — silence the secondary node so any
            // residual queue from a recent toggle clears.
            polyPlayerNode.volume = 0
        }
    }

    /// Resolve a single sound-preset key to a playable buffer at the
    /// given accent + pitch. Keys of the form `"user:<UUID>"` route
    /// through the imported-sound registry; built-in `ClickSound.rawValue`
    /// strings hit the synthesized buffer cache; anything unrecognized
    /// returns nil so the caller can fall through to the next level of
    /// the sound-resolution chain.
    private func resolveBuffer(
        forKey key: String,
        accent: AccentLevel,
        pitch: PitchShift
    ) async -> AVAudioPCMBuffer? {
        if let id = UserSound.id(fromKey: key) {
            return await userSoundRegistry.buffer(for: id, accent: accent)?.buffer
        }
        if let cs = ClickSound(rawValue: key) {
            return clickBuffers[BufferKey(sound: cs, accent: accent, pitch: pitch)]
        }
        return nil
    }

    /// Deterministic per-beat dice roll for random-mute mode (spec §6.4).
    /// All clicks at the same (measure, beat) get the same result, so a
    /// muted beat is silent across its main click + any subdivisions —
    /// preserving the "feel where the missing beat would be" training
    /// effect. The seed changes per `engine.start()`, so different
    /// practice sessions see different patterns.
    static func shouldRandomlyMute(
        measure: Int,
        beat: Int,
        seed: UInt64,
        percentage: Int
    ) -> Bool {
        guard percentage > 0 else { return false }
        // Splitmix64-style finalizer: cheap, well-mixed, deterministic.
        var x = seed
        x ^= UInt64(bitPattern: Int64(measure)) &* 0x9E3779B97F4A7C15
        x ^= UInt64(bitPattern: Int64(beat)) &* 0xBF58476D1CE4E5B9
        x ^= x >> 30
        x &*= 0xBF58476D1CE4E5B9
        x ^= x >> 27
        x &*= 0x94D049BB133111EB
        x ^= x >> 31
        return Int(x % 100) < percentage
    }

    /// `max(4, ceil(0.5s / clickPeriod))` clicks, capped at
    /// `maxLookaheadClicks` to defend against pathological combinations
    /// (e.g., 400 BPM + custom-9 subdivision yields ~31 clicks; raising
    /// either of those further would balloon the queue without
    /// audible benefit). At 400 BPM (period 150 ms) → 4 clicks
    /// (~600 ms of audio queued); at 120 BPM (500 ms) → 4 clicks
    /// (~2 s); at 60 BPM (1000 ms) → 4 clicks (~4 s). Subdivisions
    /// shrink clickPeriod and push lookahead up but stay bounded by
    /// the cap.
    private func adaptiveLookahead(for engine: MetronomeEngine) async -> Int {
        guard let schedule = await engine.schedule else {
            return Self.minLookaheadClicks
        }
        let bySeconds = Int(ceil(Self.minLookaheadSeconds / schedule.clickPeriod))
        let bounded = max(Self.minLookaheadClicks, bySeconds)
        return min(Self.maxLookaheadClicks, bounded)
    }

    // MARK: - Session activation (iOS only)

    /// Activate the shared audio session. Once active, the session
    /// stays active for the lifetime of the app — we never call
    /// `setActive(false)` ourselves. See `stop()` for the reasoning
    /// (volume-key KVO + Now Playing slot retention).
    private func activateSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioScheduler: session activate failed: \(error)")
        }
        #endif
    }
}
