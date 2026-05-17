import Foundation

#if canImport(CoreHaptics)
import CoreHaptics

/// Owns `CHHapticEngine` + an advanced pattern player and schedules
/// haptic events ahead of the engine clock — same architecture as
/// `AudioScheduler` for audio. Drives off the engine's click stream
/// so haptics stay in lockstep with audio per the CLAUDE.md mandate
/// ("haptics must fire from the same scheduling clock as audio").
///
/// Each click resolves to a transient `CHHapticEvent` whose intensity +
/// sharpness map from the click's accent level. Mute is skipped. The
/// engine's settings.hapticMode is consulted every refill pass so
/// toggling in Settings takes effect within ~50 ms.
///
/// Requires a real device with the haptic engine — Simulator doesn't
/// have one. The actor starts the engine lazily and gracefully no-ops
/// when haptics aren't available (older devices, simulator, no
/// permission, etc.) instead of crashing.
public actor HapticScheduler {
    /// Refill loop sleep interval — matches `AudioScheduler` so the
    /// two refills tend to land in the same time window.
    private static let refillIntervalMs: UInt64 = 50

    private static let minLookaheadClicks: Int = 4
    private static let minLookaheadSeconds: TimeInterval = 0.5

    private var engine: CHHapticEngine?
    private weak var engineRef: MetronomeEngine?
    private var refillTask: Task<Void, Never>?
    /// Last scheduled click time (relative to engine clock). Same
    /// purpose as `AudioScheduler.lastScheduledTime` — keeps the
    /// refill loop from re-scheduling clicks already queued.
    private var lastScheduledTime: TimeInterval = -.infinity
    /// Our own clock — same backing source as the engine's
    /// SystemClock (mach_absolute_time). Used to compute the
    /// "play this haptic N seconds from now" offset passed to
    /// CHHapticPatternPlayer.start(atTime:).
    private let clock = SystemClock()
    /// In-flight haptic players, keyed by the engine-clock time the
    /// haptic is scheduled to fire. `CHHapticPatternPlayer` instances
    /// MUST stay alive until they fire — releasing them early causes
    /// the haptic engine to fire them immediately (the cause of the
    /// "fast double-bass-pedal buzz" bug reported on 2026-05). The
    /// refill loop prunes expired entries each pass.
    private var inFlightPlayers: [(playAt: TimeInterval, player: any CHHapticPatternPlayer)] = []

    public init() {}

    /// Activate the haptic engine and begin the refill loop.
    /// No-op if device doesn't support haptics (older iPhones, simulator).
    public func start(engine metronomeEngine: MetronomeEngine) async {
        self.engineRef = metronomeEngine
        self.lastScheduledTime = -.infinity

        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        if engine == nil {
            do {
                engine = try CHHapticEngine()
                engine?.isAutoShutdownEnabled = true
                // The reset handler restarts after a media services reset.
                engine?.resetHandler = { [weak self] in
                    Task { await self?.restartEngine() }
                }
            } catch {
                print("HapticScheduler: CHHapticEngine init failed: \(error)")
                return
            }
        }

        do {
            try await engine?.start()
        } catch {
            print("HapticScheduler: engine.start failed: \(error)")
            return
        }

        refillTask?.cancel()
        refillTask = Task { [weak self] in
            await self?.refillLoop()
        }
    }

    /// Stop emitting haptics. Engine kept alive (cheap to restart) but
    /// the refill loop is cancelled and pending events are dropped.
    public func stop() async {
        refillTask?.cancel()
        refillTask = nil
        try? await engine?.stop()
        lastScheduledTime = -.infinity
        // Drop all in-flight players. The engine is stopping; anything
        // still queued either has fired (so the player is stale) or
        // shouldn't fire (engine is being shut down).
        inFlightPlayers.removeAll()
    }

    /// Drop the in-flight queue and re-anchor at the new engine clock —
    /// called by `MetronomeEngine.reanchorIfRunning()` on tempo / meter /
    /// accent edits, parallel to `AudioScheduler.scheduleReset()`.
    public func scheduleReset() async {
        lastScheduledTime = -.infinity
    }

    private func restartEngine() async {
        do { try await engine?.start() }
        catch { print("HapticScheduler: restart failed: \(error)") }
    }

    private func refillLoop() async {
        while !Task.isCancelled {
            await refillOnce()
            try? await Task.sleep(nanoseconds: Self.refillIntervalMs * 1_000_000)
        }
    }

    private func refillOnce() async {
        guard let engine = engineRef, self.engine != nil else { return }
        pruneExpiredPlayers()
        let settings = await engine.settings
        // Mode-off is the common case — short-circuit before paying for
        // the click query.
        guard settings.hapticMode != .off else { return }

        let lookahead = await adaptiveLookahead(for: engine)
        let upcoming = await engine.clicks(after: lastScheduledTime, count: lookahead)
        for click in upcoming {
            lastScheduledTime = click.time
            guard settings.hapticMode.shouldFire(for: click) else { continue }
            await scheduleEvent(forClick: click, intensity: settings.hapticIntensity)
        }
    }

    private func adaptiveLookahead(for engine: MetronomeEngine) async -> Int {
        guard let schedule = await engine.schedule else { return Self.minLookaheadClicks }
        let period = schedule.clickPeriod
        let secondsBased = Int((Self.minLookaheadSeconds / period).rounded(.up))
        return max(Self.minLookaheadClicks, secondsBased)
    }

    /// Build a one-event transient haptic and schedule it for the
    /// click's actual time. `player.start(atTime:)` takes a relative
    /// offset in seconds from "now" — we compute the offset against
    /// our SystemClock so haptics fire when the audio click does, not
    /// at the refill loop's tick rate. Earlier versions used
    /// `CHHapticTimeImmediate` (0) which fired every queued haptic
    /// instantly — producing a sustained buzz at 1/refillInterval Hz
    /// regardless of the configured mode.
    private func scheduleEvent(forClick click: Click, intensity: HapticIntensity) async {
        guard let hapticEngine = engine else { return }
        let intensityValue = Float(intensity.value(for: click.accent))
        let sharpness = Self.sharpness(for: click.accent)
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensityValue),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        // Compute when this haptic should fire. CRITICALLY,
        // CHHapticPatternPlayer.start(atTime:) takes ABSOLUTE time in
        // the haptic engine's timebase — NOT a relative offset from
        // "now." Passing a small number like 0.4 means "fire at engine
        // time 0.4," which the engine treats as the past once any
        // playback has happened — fires immediately. That was the
        // root cause of the "fast double-bass-pedal buzz" reported on
        // device. Earlier attempts in v0.13.4 and v0.13.5 fixed
        // adjacent issues but missed this one.
        //
        // Correct: anchor at `hapticEngine.currentTime` (the engine's
        // current absolute time) and add our relative offset to land
        // at the right future instant.
        let offsetFromNow = max(0, click.time - clock.now)
        let absoluteFireTime = hapticEngine.currentTime + offsetFromNow
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine.makePlayer(with: pattern)
            try player.start(atTime: absoluteFireTime)
            // Hold a strong reference until past the fire time. Even
            // with correct atTime, releasing the player too early can
            // cause CoreHaptics to drop or rush the playback.
            inFlightPlayers.append((playAt: click.time, player: player))
        } catch {
            // Don't spam logs — haptic engine can throw under load. Drop.
            _ = error
        }
    }

    /// Drop in-flight player references whose scheduled time has
    /// passed. Called from the refill loop so cleanup happens at the
    /// same cadence as scheduling — no separate timer.
    private func pruneExpiredPlayers() {
        let now = clock.now
        // Keep a small grace window (200 ms past the scheduled time)
        // before releasing. Some haptic events have non-zero duration
        // even though we use `.hapticTransient`; releasing during
        // playback could re-trigger the immediate-fire bug.
        let grace: TimeInterval = 0.2
        inFlightPlayers.removeAll { $0.playAt + grace < now }
    }

    /// Sharpness curve — kept hardcoded because it's a tactile quality,
    /// not a "loudness" knob the user should be tweaking. Higher accent
    /// levels feel "snappier."
    private static func sharpness(for accent: AccentLevel) -> Float {
        switch accent {
        case .mute:   return 0.5
        case .soft:   return 0.4
        case .normal: return 0.6
        case .loud:   return 0.8
        case .accent: return 1.0
        }
    }
}

#else

/// Stub on platforms without CoreHaptics. Lets `MetronomeEngine` keep
/// its `attach(haptic:)` API platform-agnostic.
public actor HapticScheduler {
    public init() {}
    public func start(engine: MetronomeEngine) async {}
    public func stop() async {}
    public func scheduleReset() async {}
}

#endif
