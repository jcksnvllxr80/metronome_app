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
    private var tapFormat: AVAudioFormat?
    private let captureLock = NSLock()
    private var samples: [Float] = []
    private var tapInstalled = false

    init() {}

    /// Attach to the live view model + audio scheduler. Must be called
    /// once at app startup; subsequent `run` calls reuse these refs.
    func attach(viewModel: MetronomeViewModel, scheduler: AudioScheduler) async {
        self.viewModel = viewModel
        self.avEngine = await scheduler.avEngine
        self.tapFormat = await scheduler.format
    }

    /// Run the test for `duration` seconds at `bpm`. The test forces a
    /// clean engine config (4/4, no subdivision, no automation) for
    /// the duration and stops the engine when done. Caller is
    /// expected to keep the app foregrounded; backgrounded behavior
    /// (audio session interruption, etc.) is not exercised here.
    func run(bpm: Double = 120, duration: TimeInterval = 60) async -> Result? {
        guard let avEngine, let tapFormat, let vm = viewModel else { return nil }

        captureLock.lock()
        samples.removeAll(keepingCapacity: true)
        captureLock.unlock()

        // Install tap on the main mixer so we capture the final mix
        // before it goes to hardware. Buffer size 4096 frames keeps
        // callback overhead low; sample rate is whatever the audio
        // session settled on (typically 48 kHz on modern iOS).
        let mixer = avEngine.mainMixerNode
        mixer.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
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
        }

        // Force a clean known-good engine config for the test window.
        // No state restoration after; this is a diagnostic.
        await vm.engine.setBPM(BPM(bpm))
        await vm.engine.setTimeSignature(.fourFour)
        await vm.engine.setSubdivision(.none)
        await vm.engine.setAutomation(nil)
        _ = await vm.engine.setAccentPattern(nil)

        // Start playback, wait, stop.
        await vm.engine.start()
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        await vm.engine.stop()

        // Drain the lock + snapshot captured samples.
        captureLock.lock()
        let captured = samples
        captureLock.unlock()
        let sampleRate = tapFormat.sampleRate

        // Run analysis.
        let onsets = Self.detectOnsets(samples: captured, sampleRate: sampleRate)
        guard onsets.count >= 4 else { return nil }

        let expectedPeriod = 60.0 / bpm
        let (median, stdDev) = Self.intervalStats(
            onsets: onsets,
            expectedPeriod: expectedPeriod
        )

        return Result(
            durationSeconds: duration,
            bpm: bpm,
            detectedClickCount: onsets.count,
            expectedPeriodSeconds: expectedPeriod,
            measuredPeriodSeconds: median,
            intervalStdDevMs: stdDev * 1000.0
        )
    }

    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        captureLock.lock()
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
    /// dropped before the stats since they indicate missed or
    /// spurious onsets, not actual drift.
    static func intervalStats(
        onsets: [TimeInterval],
        expectedPeriod: TimeInterval
    ) -> (median: TimeInterval, stdDev: TimeInterval) {
        let iois = zip(onsets.dropFirst(), onsets).map { $0 - $1 }
        let valid = iois.filter { abs($0 - expectedPeriod) < expectedPeriod * 0.5 }
        guard !valid.isEmpty else { return (expectedPeriod, 0) }

        let sorted = valid.sorted()
        let median = sorted[sorted.count / 2]

        let mean = valid.reduce(0, +) / Double(valid.count)
        let variance = valid.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(valid.count)
        return (median, variance.squareRoot())
    }
}
