import Foundation
import AVFoundation

/// Generates audible click buffers procedurally — no sample files needed.
///
/// Phase 1 ships 4 synthesized timbres (per `ClickSound`) covering distinct
/// sonic regions so users get an actually-useful picker on day one. The
/// generators are intentionally simple (sum-of-sinusoids + exponential
/// envelopes + RNG noise) — they're approximations, not high-fidelity
/// emulations. Real percussion samples can drop in later by branching
/// on `sound` to load from the bundle instead of synthesizing.
///
/// All buffers are mono content written to every channel of the requested
/// format. Frame count is computed from the sound's per-timbre duration.
public enum ClickBufferGenerator {
    /// Build a click buffer matching the given accent level and sound.
    /// Returns `nil` if the AV layer can't allocate (rare).
    public static func makeBuffer(
        format: AVAudioFormat,
        accent: AccentLevel,
        sound: ClickSound
    ) -> AVAudioPCMBuffer? {
        // Mute clicks: zero-amplitude buffer of the sound's natural length.
        // Keeping the slot in the schedule keeps lastScheduledTime tracking
        // straightforward even though no audio plays.
        if accent == .mute {
            return silentBuffer(format: format, duration: 0.040)
        }
        switch sound {
        case .digitalBeep: return makeDigitalBeep(format: format, accent: accent)
        case .woodBlock:   return makeWoodBlock(format: format, accent: accent)
        case .cowbell:     return makeCowbell(format: format, accent: accent)
        case .hiHat:       return makeHiHat(format: format, accent: accent)
        }
    }

    // MARK: - Amplitude / pitch tables

    /// 0...1 amplitude per accent level. Shared across all sounds so
    /// accent dynamics feel consistent when the user switches timbres.
    private static func amplitude(for accent: AccentLevel) -> Float {
        switch accent {
        case .mute:   0.00
        case .soft:   0.20
        case .normal: 0.55
        case .loud:   0.85
        case .accent: 1.00
        }
    }

    /// Pitch multiplier per accent — lower freq = more weight. Applied to
    /// tonal sounds (wood block, digital beep). Hi-hat and noise sounds
    /// ignore this since pitch isn't a useful axis there.
    private static func pitchMultiplier(for accent: AccentLevel) -> Double {
        switch accent {
        case .mute, .soft: 1.25
        case .normal:      1.00
        case .loud:        0.85
        case .accent:      0.67
        }
    }

    // MARK: - Voices

    /// Pure sine burst with exponential decay. 40 ms, frequency ~800–1500 Hz
    /// depending on accent. The Phase 0/A baseline timbre — clean, electronic.
    private static func makeDigitalBeep(
        format: AVAudioFormat,
        accent: AccentLevel
    ) -> AVAudioPCMBuffer? {
        let durationSec = 0.040
        let baseFreq = 1200.0
        let frequency = baseFreq * pitchMultiplier(for: accent)
        let amp = amplitude(for: accent)
        // -40 dB over duration
        let decayRate = log(0.01) / durationSec
        return writeBuffer(format: format, durationSec: durationSec) { t in
            let env = Float(exp(decayRate * t))
            return amp * env * Float(sin(2.0 * .pi * frequency * t))
        }
    }

    /// Sharp tonal attack with fast decay. 35 ms, three harmonics around
    /// 1200 Hz fundamental. Mimics a hardwood block strike — dry, woody,
    /// percussive.
    private static func makeWoodBlock(
        format: AVAudioFormat,
        accent: AccentLevel
    ) -> AVAudioPCMBuffer? {
        let durationSec = 0.035
        let pitchMul = pitchMultiplier(for: accent)
        let f1 = 1200.0 * pitchMul
        let f2 = 2400.0 * pitchMul
        let f3 = 3600.0 * pitchMul
        let amp = amplitude(for: accent)
        // -60 dB in 25 ms — very fast "knock"
        let decayRate = log(0.001) / 0.025
        return writeBuffer(format: format, durationSec: durationSec) { t in
            let env = Float(exp(decayRate * t))
            let s1 = sin(2.0 * .pi * f1 * t)
            let s2 = 0.4 * sin(2.0 * .pi * f2 * t)
            let s3 = 0.2 * sin(2.0 * .pi * f3 * t)
            // 0.7 attenuation keeps the 3-partial sum under 1.0 peak.
            return amp * env * Float(s1 + s2 + s3) * 0.7
        }
    }

    /// Two-partial resonance with a brief attack-noise burst. 150 ms,
    /// 590 Hz + 845 Hz (cowbell partial ratios from psychoacoustics
    /// research). Mid-range sustain with a metallic edge.
    private static func makeCowbell(
        format: AVAudioFormat,
        accent: AccentLevel
    ) -> AVAudioPCMBuffer? {
        let durationSec = 0.150
        let f1 = 590.0
        let f2 = 845.0
        let amp = amplitude(for: accent)
        // -40 dB in 150 ms — medium sustain
        let decayRate = log(0.01) / 0.150
        // Brief noise transient at the attack (first 8 ms)
        let attackNoiseDur = 0.008
        let attackNoiseAmp: Float = 0.30

        var rng = SystemRandomNumberGenerator()
        return writeBuffer(format: format, durationSec: durationSec) { t in
            let env = Float(exp(decayRate * t))
            let tone = sin(2.0 * .pi * f1 * t) + 0.65 * sin(2.0 * .pi * f2 * t)
            var sample = amp * env * Float(tone) * 0.55
            if t < attackNoiseDur {
                let noise = Float.random(in: -1...1, using: &rng)
                let noiseEnv = Float(1.0 - t / attackNoiseDur) // linear ramp-down
                sample += amp * noiseEnv * attackNoiseAmp * noise
            }
            return sample
        }
    }

    /// Broadband noise burst with high-frequency tonal partials for a
    /// metallic shimmer. 60 ms, very fast decay. Hi-hat-adjacent —
    /// the picker option for users who want a "tss" not a "knock."
    private static func makeHiHat(
        format: AVAudioFormat,
        accent: AccentLevel
    ) -> AVAudioPCMBuffer? {
        let durationSec = 0.060
        let amp = amplitude(for: accent)
        // -60 dB in 40 ms
        let decayRate = log(0.001) / 0.040
        var rng = SystemRandomNumberGenerator()
        return writeBuffer(format: format, durationSec: durationSec) { t in
            let env = Float(exp(decayRate * t))
            let noise = Float.random(in: -1...1, using: &rng) * 0.6
            // High-frequency partials add a "metallic" character on top
            // of the noise floor.
            let hf1 = 0.30 * Float(sin(2.0 * .pi * 8000.0 * t))
            let hf2 = 0.20 * Float(sin(2.0 * .pi * 12000.0 * t))
            return amp * env * (noise + hf1 + hf2)
        }
    }

    // MARK: - Buffer plumbing

    /// Allocate a buffer of `durationSec` and run `sampleAt` for each frame,
    /// writing the same value to all channels. Returns `nil` if AV refuses
    /// to allocate.
    private static func writeBuffer(
        format: AVAudioFormat,
        durationSec: Double,
        sampleAt: (_ t: Double) -> Float
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * durationSec)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(buffer.format.channelCount)
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let sample = sampleAt(t)
            for ch in 0..<channelCount {
                channelData[ch][frame] = sample
            }
        }
        return buffer
    }

    private static func silentBuffer(
        format: AVAudioFormat,
        duration: Double
    ) -> AVAudioPCMBuffer? {
        writeBuffer(format: format, durationSec: duration) { _ in 0 }
    }
}
