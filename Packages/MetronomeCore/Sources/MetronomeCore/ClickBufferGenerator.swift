import Foundation
import AVFoundation

/// Generates audible click buffers procedurally — no sample files needed yet.
///
/// Sub-commit B intentionally uses synthesized tone bursts instead of real
/// percussion samples (wood block, cowbell, etc.) so the first audible
/// commit doesn't depend on bundling 12+ asset files. Each `AccentLevel`
/// gets its own frequency + amplitude so accent patterns are audibly
/// distinct from day one. Sub-commit C swaps these for the Phase 1 sound
/// library.
public enum ClickBufferGenerator {
    /// 40 ms tone burst with exponential decay envelope. Different accent
    /// levels modulate frequency (lower = more weight) and amplitude.
    public static func makeBuffer(
        format: AVAudioFormat,
        accent: AccentLevel
    ) -> AVAudioPCMBuffer? {
        let durationSeconds: Double = 0.040
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount

        let amplitude: Float
        let frequency: Double
        switch accent {
        case .mute:
            amplitude = 0.0
            frequency = 1000.0
        case .soft:
            amplitude = 0.20
            frequency = 1500.0
        case .normal:
            amplitude = 0.55
            frequency = 1200.0
        case .loud:
            amplitude = 0.85
            frequency = 1000.0
        case .accent:
            amplitude = 1.0
            frequency =  800.0
        }

        // Exponential decay from peak to -40 dB over the duration.
        let decayRate = log(0.01) / durationSeconds
        let twoPiF = 2.0 * .pi * frequency

        // Write to all channels (mono → 1, stereo → 2, etc.)
        guard let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(buffer.format.channelCount)
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let envelope = Float(exp(decayRate * t))
            let sample = amplitude * envelope * Float(sin(twoPiF * t))
            for channel in 0..<channelCount {
                channelData[channel][frame] = sample
            }
        }

        return buffer
    }
}
