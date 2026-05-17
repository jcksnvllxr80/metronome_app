Metronome App — Functional Specification
Target platform: iOS 17+ (Swift 5.9+, SwiftUI) Scope: Operational/feature specification — UI/visual design intentionally excluded. This document defines what the app does, not what it looks like.

1. Core Timing Engine
1.1 Requirements
Tempo range: 20–400 BPM, adjustable in 0.1 BPM increments (display rounded to whole BPM by default; precision mode in settings).
Timing accuracy: drift must be < 1 ms per minute over sustained playback.
Must continue accurately when app is backgrounded, screen is locked, or device is in silent mode.
1.2 Implementation approach
Use AVAudioEngine with sample-accurate scheduling via AVAudioPlayerNode.scheduleBuffer(at:).
Do not use Timer or DispatchSourceTimer for click scheduling — both drift under load.
Pre-schedule clicks N beats ahead (suggest 4–8 beats lookahead) and refill on a background queue.
Use mach_absolute_time / AVAudioTime for reference clock.
Audio session category: .playback with .mixWithOthers option (so it can run alongside music apps and tuners).
Configure AVAudioSession to remain active in background; declare audio background mode in Info.plist.

2. Time Signature & Subdivision
2.1 Time signature
Numerator: 1–32
Denominator: 1, 2, 4, 8, 16, 32
Common presets: 2/4, 3/4, 4/4, 5/4, 6/8, 7/8, 9/8, 12/8
Custom/odd meters fully supported.
2.2 Compound and complex meters
Support grouped subdivisions for odd meters (e.g., 7/8 as 2+2+3, 3+2+2, 2+3+2).
User can define accent groupings per time signature.
2.3 Subdivisions per beat
Off (quarter notes only)
Eighths (2 per beat)
Eighth triplets (3 per beat)
Sixteenths (4 per beat)
Quintuplets (5 per beat)
Sextuplets (6 per beat)
Septuplets (7 per beat)
Custom: 8, 9 per beat
Each subdivision level has independent volume and optional independent sound.
2.4 Polyrhythm mode
Two simultaneous independent meters (e.g., 3 against 4, 5 against 7).
Each meter has independent sound and volume.
Visual indicator should show both pulse streams.

3. Accent & Beat Pattern System
3.1 Per-beat configuration
For each beat in the measure, user can independently set:
Accent level: mute / soft / normal / loud / accent
Sound override: use a different click sound for this beat
Pitch override: ±1 octave shift
3.2 Pattern memory
Save accent patterns as named presets, scoped to a time signature.
Quick toggle: standard accent (downbeat only) vs. custom pattern.

4. Sound Library
4.1 Built-in click sounds (minimum set)
Classic mechanical metronome (wood block)
Digital beep (high + low pair)
Cowbell
Clave
Hi-hat / closed hat
Rim shot
Side stick
Kick drum
Snare
Shaker
Tambourine
Electronic clicks (multiple variants)
Vocal count ("1, 2, 3, 4" — see Section 5)
4.2 Sound configuration
Independent sound assignment for: downbeat, accented beats, normal beats, subdivisions.
Per-sound volume trim.
Optional user-imported sounds (WAV/AIFF/CAF, <2s, <1MB each) via Files app integration.

5. Voice Count Mode
Spoken beat numbers (pre-recorded samples; do not use AVSpeechSynthesizer — too slow/unreliable for tight timing).
Languages: English, Spanish, French, German, Japanese (extensible).
Male and female voice variants.
Count modes:
Count beats ("one, two, three, four")
Count subdivisions ("one-and-two-and" / "one-e-and-a")
Count measures (announce measure number at downbeat)
Silent count training (only count first N beats of each measure, mute the rest)

6. Tempo Features
6.1 Tap tempo
User taps a button to set BPM.
Average over last 4 taps (rolling window).
Reset window after 2 seconds of inactivity.
Visual feedback per tap.
6.2 Tempo presets
Standard Italian tempo markings as quick-set chips:
Largo (40–60), Larghetto (60–66), Adagio (66–76), Andante (76–108), Moderato (108–120), Allegro (120–168), Vivace (168–176), Presto (168–200), Prestissimo (200+).
6.3 Tempo automation
Gradual tempo change (accelerando / ritardando): start BPM, end BPM, over N beats / N measures / N seconds.
Step tempo change: increase by X BPM every N measures.
Tempo ramp loops: cycle through multiple tempo targets.
6.4 Speed trainer
Practice mode: start at slow BPM, increase by X BPM every N measures or N successful loops.
Optional ceiling BPM where it stops or reverses.
"Random mute" mode: randomly mute 10–50% of beats (user-set %) to train internal time.

7. Setlist & Song Mode
7.1 Songs
Named entries with: title, tempo, time signature, subdivision, accent pattern, sound preset, optional notes field.
Optional song duration (auto-stop after N measures or N seconds).
7.2 Setlists
Ordered collection of songs.
Auto-advance to next song (with configurable gap: pause / countdown / immediate).
Manual advance via tap, hardware button (volume keys if enabled), or Bluetooth pedal.
Reorder via drag.
7.3 Complex song structures (advanced)
Multi-section songs: each section has its own tempo/meter/measures (e.g., intro 16 bars @ 90, verse 32 bars @ 120, bridge 8 bars @ 100).
Repeat markers / DC al fine logic optional but useful.

8. Visual Pulse / Beat Indication
Operational requirements only — UI execution left to the implementing model:
Visual indicator must pulse on every beat, with distinct treatment for downbeat / accented / subdivided beats.
Must remain frame-accurate at 60fps (use CADisplayLink or SwiftUI TimelineView synced to audio clock, not independent timers).
Optional full-screen flash mode for use on stage.
Optional swing pendulum mode (analog metronome visualization).

9. Haptic Feedback
Use CoreHaptics (CHHapticEngine) for downbeats, accents, and optionally every beat.
Haptic patterns must be triggered from the same scheduling clock as the audio.
User toggleable: off / downbeat only / accents only / every beat / subdivisions too.
Configurable haptic intensity per accent level.
Apple Watch companion (Section 13) handles wrist haptics.

10. Settings & Preferences
10.1 Audio settings
Master volume.
Latency calibration (let user manually offset audio output by ±50 ms for Bluetooth headphones).
Output routing display (current output device).
Mix-with-others toggle.
10.2 Behavior settings
Count-in: off / 1 / 2 / 4 measures before playback starts.
Auto-stop after N minutes of inactivity (optional).
Lock screen behavior: stay on / dim / sleep.
Keep screen awake during playback toggle.
Start on app launch toggle.
10.3 Display settings
BPM precision (whole / 0.1)
Theme: light / dark / system
Reduce motion respect (UIAccessibility.isReduceMotionEnabled)
Large display mode (huge BPM readout for stage use)
10.4 Input settings
Allow hardware volume keys to start/stop.
Bluetooth foot pedal support (see Section 12).
Headphone remote button mapping.

11. Practice & Statistics
Practice session log: date, duration, tempo range, songs played.
Total practice time per day/week/month.
Per-song play count and average tempo.
Optional goal tracking (daily practice minutes).
Export practice log as CSV.
Storage: SwiftData (iOS 17+) or Core Data fallback. Local only by default; iCloud sync optional (Section 14).

12. External Hardware Integration
12.1 Bluetooth foot pedals
Support standard BLE MIDI pedals (PageFlip Firefly, AirTurn, Donner, etc.).
Configurable actions: start/stop, tap tempo, next song, previous song, tempo up/down.
12.2 MIDI sync
Send MIDI Clock out via Bluetooth MIDI / USB MIDI / Network MIDI.
Send MIDI Start/Stop/Continue.
Optionally receive MIDI Clock (sync as slave to a DAW or another device).
Use CoreMIDI framework.
12.3 Ableton Link
Integrate Ableton Link SDK for tempo sync with other Link-enabled apps on the same Wi-Fi network. Major selling point — most pro metronomes have this.

13. Apple Watch Companion
Standalone watchOS target.
Mirror tempo and start/stop with iPhone via WatchConnectivity.
Independent operation: full metronome on watch alone.
Haptic-only mode (silent click via taptic engine — extremely useful for live performance).
Complications: current BPM, quick start.

14. iCloud Sync (optional)
Sync songs, setlists, sound presets, accent patterns, practice log.
Use CloudKit via SwiftData/CoreData CloudKit integration.
Conflict resolution: last-write-wins acceptable for this domain.

15. Accessibility
Full VoiceOver support — every control labeled, BPM changes announced.
Dynamic Type compliance.
Reduce Motion respected for visual pulse.
High contrast mode support.
Switch Control compatible.
Audio-only operation must be fully functional (blind-accessible).

16. Background & Lifecycle
Continue playback when backgrounded, locked, in Control Center, or in another app.
Now Playing info via MPNowPlayingInfoCenter showing tempo and song name.
Lock screen / Control Center playback controls via MPRemoteCommandCenter:
Play/pause
Next/previous (in setlist mode)
Handle audio interruptions (calls, Siri) — pause cleanly, optionally auto-resume.
Handle route changes (headphone unplug → pause; recommended default per Apple HIG).

17. Architecture Recommendations
App architecture: MVVM with SwiftUI views observing @Observable view models (iOS 17 Observation framework, not legacy ObservableObject).
Audio engine: isolated actor (@MainActor avoided — use a custom audio actor or a serial dispatch queue for scheduling).
State management: central MetronomeEngine class owning the AVAudioEngine; view models read from it via Combine or Observation.
Persistence: SwiftData models for Song, Setlist, SoundPreset, AccentPattern, PracticeSession.
Modular packages: consider splitting into Swift Packages — MetronomeCore (engine), MetronomeUI (views), MetronomePersistence (data) — for testability.
Testing: unit-test the timing engine with a fake clock; verify scheduled-event accuracy in isolation from audio output.

18. Frameworks Required
SwiftUI
AVFoundation / AVFAudio
CoreHaptics
CoreMIDI
MediaPlayer (for Now Playing / Remote Command Center)
WatchConnectivity (if Watch app included)
SwiftData (or CoreData)
CloudKit (if sync included)
Combine (where Observation isn't sufficient)
Accelerate (if any DSP needed for custom click synthesis)
Ableton Link (external SDK, MIT licensed)

19. Build / Ship Requirements
iOS deployment target: 17.0
Required device capabilities: armv7 removed; arm64 only
Info.plist keys needed:
UIBackgroundModes: audio
NSMicrophoneUsageDescription only if tap-tempo-by-mic is implemented (optional feature)
App Store category: Music
Audio session category: .playback, options [.mixWithOthers]

20. Out of Scope (explicitly excluded)
Visual/aesthetic design (left to the implementing model)
Marketing copy, app icon, screenshots
Monetization model (free / paid / freemium — to be decided)
Server-side components (app is offline-first)
Audio recording or DAW features
Social / sharing features

21. Implementation Priority (suggested phasing)
Phase 1 — MVP (engine + core UX): Sections 1, 2.1–2.3, 3, 4.1, 6.1–6.2, 8 (basic), 10.1–10.3, 16.
Phase 2 — Practice tools: Sections 5, 6.3–6.4, 7.1–7.2, 9, 11.
Phase 3 — Pro features: Sections 2.4, 7.3, 12, 13, 14.
Phase 4 — Polish: Section 15 (accessibility audit), latency tuning, edge cases.

This spec should be enough for a Swift-capable model with Xcode access to scaffold the project and implement features incrementally. Hand it Phase 1 first; don't ask for the whole thing in one shot.
Would you like me to save this as a markdown file you can drop into the project?