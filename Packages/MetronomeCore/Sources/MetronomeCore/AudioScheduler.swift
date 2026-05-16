import Foundation
import AVFoundation

/// Owns the `AVAudioEngine` and schedules click buffers ahead of the engine
/// clock. **Sub-commit A: shell only — no buffers are scheduled, no sound
/// is produced.** Construction wires up an `AVAudioEngine` and one
/// `AVAudioPlayerNode` and connects them to the main mixer, but doesn't
/// start the engine or schedule anything.
///
/// Sub-commit B will:
/// 1. Activate the audio session
/// 2. Start the `AVAudioEngine`
/// 3. Start the player node
/// 4. Begin the refill loop fed by `MetronomeEngine.upcomingClicks(count:)`
///
/// Sub-commit C handles interruption + route changes, lookahead policy,
/// and the full Phase 1 sound library.
public actor AudioScheduler {
    public let avEngine: AVAudioEngine
    public let playerNode: AVAudioPlayerNode

    public init() {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        // Connect to the main mixer using its native format. Sub-commit B
        // will pin this to a fixed format that matches the bundled samples
        // so we don't pay a per-click resampling cost.
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        self.avEngine = engine
        self.playerNode = node
    }

    /// Sub-commit B will: activate session, start engine, start player node,
    /// kick off the refill loop. Today: no-op.
    public func start() {
        // Intentionally empty.
    }

    /// Sub-commit B will: stop player node, stop engine, clear pending
    /// scheduled buffers. Today: no-op.
    public func stop() {
        // Intentionally empty.
    }
}
