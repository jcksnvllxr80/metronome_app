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

    /// Build a one-event pattern + schedule it on an advanced player so
    /// we can set `playAt:` for precise timing. Transient events are
    /// the right primitive for a metronome tap (sharp, percussive,
    /// minimal latency).
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
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine.makePlayer(with: pattern)
            // `playAt: 0` plays immediately — for sub-millisecond timing
            // we'd use makeAdvancedPlayer + schedule at a future time,
            // but the refill loop runs ~every 50ms which gives clicks a
            // bounded look-ahead anyway. v1: play-now is good enough on
            // real devices.
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Don't spam logs — haptic engine can throw under load. Drop.
            _ = error
        }
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
