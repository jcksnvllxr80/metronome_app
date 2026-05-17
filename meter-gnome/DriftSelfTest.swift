//
//  DriftSelfTest.swift
//  meter-gnome
//
//  In-app verification of the spec §1.1 drift budget (< 1 ms/minute).
//  Taps `AVAudioEngine.mainMixerNode` to capture the metronome's own
//  rendered audio post-mix but pre-hardware-output, then runs a simple
//  RMS-energy onset detector + median inter-onset-interval analysis
//  to measure the actual click period the engine produced. Compares
//  to the expected period (60 / BPM) and reports drift in ms/min.
//
//  No mic permission required: we sample our own output, not the room.
//  Mic-to-speaker distance and capture-pipeline latency would have been
//  irrelevant for drift anyway (constants cancel out of spacing
//  measurements), but routing through the internal tap also rules out
//  room reverb + ambient noise polluting onset detection.
//
//  Scope is intentionally narrow — this is a developer-grade diagnostic
//  behind Settings → Diagnostics. The test forces a clean engine state
//  (120 BPM by default, 4/4, no subdivisions, no song / automation)
//  for the test window. State is not restored after; the user is
//  expected to know they're running a diagnostic.
//

import Foundation
import AVFoundation
import MetronomeCore

/// One-shot drift self-test runner. Not a singleton — `meter_gnomeApp`
/// constructs one alongside the other coordinators and the view model
/// holds a reference. Re-runnable; each run resets internal state.
///
/// Concurrency: marked `@unchecked Sendable` because the audio tap
/// callback fires off an audio thread and appends into the sample
/// buffer under an `NSLock`. The capture path is straightforward and
/// confined to this file.
final class DriftSelfTest: @unchecked Sendable {
    /// Result of one self-test run. All time values are in seconds
    /// except `driftMsPerMinute` which is reported in milliseconds for
    /// direct comparison to the spec §1.1 budget.
    struct Result: Sendable {
        let durationSeconds: TimeInterval
        let bpm: Double
        let detectedClickCount: Int
        let expectedPeriodSeconds: TimeInterval
        let measuredPeriodSeconds: TimeInterval
        /// Standard deviation of inter-onset intervals (post-filtering),
        /// in milliseconds. Sanity check: if this is large, the onset
        /// detector hit noise rather than clean clicks and the drift
        /// number is suspect.
        let intervalStdDevMs: Double
        /// Inter-onset intervals in milliseconds, in capture order.
        /// Drives the IOI plot in the diagnostics view so users can
        /// see per-click distribution rather than just the median.
        let intervalsMs: [Double]
        /// Sample rate the captured audio buffers actually arrived at.
        /// Exposed for sanity-check display since a mismatch between
        /// expected and actual sample rate was the root cause of the
        /// first v0.34.0 false-positive drift result.
        let sampleRateHz: Double

        /// Positive = the engine's measured period is longer than
        /// expected (running slow); negative = running fast.
        var driftMsPerMinute: Double {
            let driftSecPerClick = measuredPeriodSeconds - expectedPeriodSeconds
            let clicksPerMinute = 60.0 / expectedPeriodSeconds
            return driftSecPerClick * clicksPerMinute * 1000.0
        }

        var withinSpec: Bool { abs(driftMsPerMinute) < 1.0 }
    }

    /// Spec §1.1 drift budget.
    static let specBudgetMsPerMinute: Double = 1.0

    private weak var viewModel: MetronomeViewModel?
    private var avEngine: AVAudioEngine?
    private let captureLock = NSLock()
    private var samples: [Float] = []
    /// Sample rate observed in the first audio buffer received from the
    /// tap. v0.34.0 mistakenly used `scheduler.format.sampleRate` which
    /// was captured at app-init time (before the audio session
    /// activated) and didn't match the rate iOS actually rendered at
    /// once the session was live — causing a stale-rate-of-44.1kHz vs
    /// live-rate-of-48kHz mismatch and reporting clicks as if they were
    /// 8.8% slower than scheduled. Reading the buffer's own format
    /// inside the tap callback gets the real number.
    private var observedSampleRate: Double = 0
    private var tapInstalled = false

    init() {}

    /// Attach to the live view model + audio scheduler. Must be called
    /// once at app startup; subsequent `run` calls reuse these refs.
    /// The format is intentionally NOT cached here — see the
    /// `observedSampleRate` field for why.
    func attach(viewModel: MetronomeViewModel, scheduler: AudioScheduler) async {
        self.viewModel = viewModel
        self.avEngine = await scheduler.avEngine
    }

    /// Run the test for `duration` seconds at `bpm`. The test forces a
    /// clean engine config (4/4, no subdivision, no automation) for
    /// the duration and stops the engine when done. Caller is
    /// expected to keep the app foregrounded; backgrounded behavior
    /// (audio session interruption, etc.) is not exercised here.
    func run(bpm: Double = 120, duration: TimeInterval = 60) async -> Result? {
        guard let avEngine, let vm = viewModel else { return nil }

        captureLock.lock()
        samples.removeAll(keepingCapacity: true)
        observedSampleRate = 0
        captureLock.unlock()

        // Snapshot engine settings + song-level overrides so the test
        // can force a clean known-good config (BPM 120, 4/4, no
        // subdivision/automation/polyrhythm/voice/random-mute) for the
        // duration and restore the user's state afterward. Without
        // this, a song that had polyrhythm or random-mute enabled
        // would pollute the captured audio with extra or missing
        // clicks and the drift number would be meaningless.
        let originalSettings = await vm.engine.settings
        let originalSoundPreset = await vm.engine.currentSoundPreset
        let originalPolyOverride = await vm.engine.currentPolyrhythmOverride
        var testSettings = originalSettings
        testSettings.polyrhythm = nil
        testSettings.voiceCountMode = .off
        testSettings.randomMutePercentage = 0
        testSettings.subdivisionConfigs = [:]
        await vm.engine.setSettings(testSettings)
        await vm.engine.setSoundPreset(nil)
        await vm.engine.setPolyrhythmOverride(nil)

        // Install tap on the main mixer so we capture the final mix
        // before it goes to hardware. Passing the node's live output
        // format (queried right now, not at app launch) ensures the
        // tap callbacks deliver buffers at the rate iOS is actually
        // rendering at. Buffer size 4096 keeps callback overhead low.
        let mixer = avEngine.mainMixerNode
        let liveFormat = mixer.outputFormat(forBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 4096, format: liveFormat) { [weak self] buffer, _ in
            self?.appendBuffer(buffer)
        }
        tapInstalled = true
        // Defensive remove on exit — tap-still-installed when the
        // engine stops would log a CoreAudio assertion.
        defer {
            if tapInstalled {
                mixer.removeTap(onBus: 0)
                tapInstalled = false
            }
            // Restore the user's engine state. Important even if the
            // test errored out partway through — leaving the user with
            // their polyrhythm disabled would be a worse bug than the
            // one we're diagnosing.
            Task { @MainActor [vm, originalSettings, originalSoundPreset, originalPolyOverride] in
                await vm.engine.setSettings(originalSettings)
                await vm.engine.setSoundPreset(originalSoundPreset)
                await vm.engine.setPolyrhythmOverride(originalPolyOverride)
            }
        }

        // Force test-only engine state on top of the snapshot.
        await vm.engine.setBPM(BPM(bpm))
        await vm.engine.setTimeSignature(.fourFour)
        await vm.engine.setSubdivision(.none)
        await vm.engine.setAutomation(nil)
        _ = await vm.engine.setAccentPattern(nil)

        // Start playback, wait, stop.
        await vm.engine.start()
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        await vm.engine.stop()

        // Drain the lock + snapshot captured samples + the rate we
        // saw in the first buffer (used for time-axis math).
        captureLock.lock()
        let captured = samples
        let sampleRate = observedSampleRate > 0 ? observedSampleRate : liveFormat.sampleRate
        captureLock.unlock()

        // Run analysis.
        let onsets = Self.detectOnsets(samples: captured, sampleRate: sampleRate)
        guard onsets.count >= 4 else { return nil }

        let expectedPeriod = 60.0 / bpm
        let (median, stdDev, intervalsMs) = Self.intervalStats(
            onsets: onsets,
            expectedPeriod: expectedPeriod
        )

        return Result(
            durationSeconds: duration,
            bpm: bpm,
            detectedClickCount: onsets.count,
            expectedPeriodSeconds: expectedPeriod,
            measuredPeriodSeconds: median,
            intervalStdDevMs: stdDev * 1000.0,
            intervalsMs: intervalsMs,
            sampleRateHz: sampleRate
        )
    }

    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        captureLock.lock()
        if observedSampleRate == 0 {
            observedSampleRate = buffer.format.sampleRate
        }
        samples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))
        captureLock.unlock()
    }

    // MARK: - Analysis

    /// Detect click onsets in the captured audio. Uses a windowed RMS
    /// envelope + amplitude threshold + refractory period. The internal
    /// tap captures audio with essentially zero background noise (we're
    /// upstream of speaker / room), so a fixed absolute threshold is
    /// reliable here.
    static func detectOnsets(samples: [Float], sampleRate: Double) -> [TimeInterval] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        let windowSize = max(1, Int(0.005 * sampleRate))  // 5ms windows
        let hopSize = max(1, windowSize / 2)
        // Refractory: 150ms covers the fastest realistic click period
        // (400 BPM quarters = 150ms apart). Drift test runs at 120 BPM
        // by default, so this is comfortable headroom.
        let refractorySamples = Int(0.150 * sampleRate)
        let threshold: Float = 0.02  // ~ -34 dBFS

        var onsets: [TimeInterval] = []
        var lastOnsetSample = -refractorySamples

        var i = 0
        while i + windowSize < samples.count {
            var energy: Float = 0
            for j in 0..<windowSize {
                let s = samples[i + j]
                energy += s * s
            }
            energy = (energy / Float(windowSize)).squareRoot()  // RMS

            if energy > threshold && (i - lastOnsetSample) > refractorySamples {
                onsets.append(Double(i) / sampleRate)
                lastOnsetSample = i
            }
            i += hopSize
        }

        return onsets
    }

    /// Compute the median inter-onset interval (the "measured period")
    /// and the standard deviation of the filtered intervals. Outliers
    /// — anything more than 50% off the expected period — are
    /// dropped from the median + std-dev computation since they
    /// indicate missed or spurious onsets, not actual drift. The
    /// raw intervals (in milliseconds, in capture order) are also
    /// returned so the UI can plot them — outliers included so the
    /// user can see them visually.
    static func intervalStats(
        onsets: [TimeInterval],
        expectedPeriod: TimeInterval
    ) -> (median: TimeInterval, stdDev: TimeInterval, intervalsMs: [Double]) {
        let iois = zip(onsets.dropFirst(), onsets).map { $0 - $1 }
        let valid = iois.filter { abs($0 - expectedPeriod) < expectedPeriod * 0.5 }
        let intervalsMs = iois.map { $0 * 1000.0 }
        guard !valid.isEmpty else { return (expectedPeriod, 0, intervalsMs) }

        let sorted = valid.sorted()
        let median = sorted[sorted.count / 2]

        let mean = valid.reduce(0, +) / Double(valid.count)
        let variance = valid.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(valid.count)
        return (median, variance.squareRoot(), intervalsMs)
    }
}
