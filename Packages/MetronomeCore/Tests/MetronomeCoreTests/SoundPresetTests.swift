import Testing
import Foundation
@testable import MetronomeCore

@Test func engineHasNoPresetByDefault() async {
    let engine = MetronomeEngine(clock: FakeClock())
    let preset = await engine.currentSoundPreset
    #expect(preset == nil)
}

@Test func applyingSongSetsCurrentSoundPreset() async {
    let engine = MetronomeEngine(clock: FakeClock())
    let song = Song(
        title: "Cowbell Anthem",
        bpm: BPM(120),
        soundPreset: ClickSound.cowbell.rawValue
    )!
    await engine.apply(song)
    let preset = await engine.currentSoundPreset
    #expect(preset == "cowbell")
}

@Test func applyingSongWithoutPresetClearsCurrentPreset() async {
    let engine = MetronomeEngine(clock: FakeClock())
    // Load a song with a preset first
    let songA = Song(title: "A", bpm: BPM(100), soundPreset: "hiHat")!
    await engine.apply(songA)
    // Then a song without one — the engine should clear back to nil
    let songB = Song(title: "B", bpm: BPM(100))!
    await engine.apply(songB)
    let preset = await engine.currentSoundPreset
    #expect(preset == nil)
}

@Test func stoppingClearsCurrentSoundPreset() async {
    let engine = MetronomeEngine(clock: FakeClock())
    let song = Song(title: "X", bpm: BPM(120), soundPreset: "woodBlock")!
    await engine.apply(song)
    await engine.start()
    await engine.stop()
    let preset = await engine.currentSoundPreset
    #expect(preset == nil, "stop() clears the loaded song's preset")
}

@Test func currentSoundPresetSurvivesBPMChange() async {
    let engine = MetronomeEngine(clock: FakeClock())
    let song = Song(title: "X", bpm: BPM(120), soundPreset: "cowbell")!
    await engine.apply(song)
    await engine.setBPM(BPM(140))
    let preset = await engine.currentSoundPreset
    #expect(preset == "cowbell", "Tempo nudges shouldn't drop the sound choice")
}

@Test func unknownPresetStringSurvivesOnEngine() async {
    // Engine stores whatever preset string the song carries — it's the
    // scheduler's job to fall back when the string doesn't resolve to a
    // known ClickSound. The engine doesn't enforce knownness.
    let engine = MetronomeEngine(clock: FakeClock())
    let song = Song(title: "Custom", bpm: BPM(120), soundPreset: "user-imported.wav")!
    await engine.apply(song)
    let preset = await engine.currentSoundPreset
    #expect(preset == "user-imported.wav")
}
