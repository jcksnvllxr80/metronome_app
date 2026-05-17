# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status

This repo contains the `meter-gnome` iOS app target (SwiftUI, `meter-gnome.xcodeproj`) and the local `MetronomeCore` Swift package at `Packages/MetronomeCore/` (engine math, schedulers, value types). **Phases 1 + 2 shipped; most of Phase 3 shipped.** Latest tag: **v0.26.0**. What's live: synthesized click audio via `AudioScheduler`, MIDI Clock send + receive, SwiftData persistence, library/setlist UI with auto-advance across all three modes, multi-section songs (D.C. al Fine + per-section settings + setlist integration), accent pattern editor + preset library, tempo automation (gradual / step / loop) with ceiling stop-or-reverse, speed trainer (random mute + step), practice stats, haptics, per-subdivision-level click config (§2.3), Large Display mode (§10.3), per-song sound preset Stage indicator, background + interruption + route-change handling, Now Playing + Remote Command Center. Remaining work is tracked in `TODO.md`. The original spec lives at `FUNCTIONAL_SPEC.md`; `AUDIO_INTEGRATION_PLAN.md` is the original audio plan (largely executed, kept for reference). CLAUDE.md is the source of truth for non-obvious architectural constraints — read it before changing engine code, audio code, or anything that affects timing.

## Build & test

```sh
# Run engine tests (fast, no audio, no UI — ~20ms, 345 tests)
cd Packages/MetronomeCore && swift test

# Run a single test
cd Packages/MetronomeCore && swift test --filter ClickScheduleTests

# Build the iOS app from CLI
xcodebuild -project meter-gnome.xcodeproj -scheme meter-gnome \
           -sdk iphonesimulator \
           -destination 'generic/platform=iOS Simulator' build
```

Audio timing, MIDI virtual sources, haptics, and background audio require a **real device** — simulator is unreliable for any timing claim. See README "Run on a real iPhone" for signing + trust steps.

## Target platform

- **iOS 26.5+ deployment target**, Xcode 26.5, Swift 6.x, SwiftUI. (Spec §19 says iOS 17+ minimum; project deliberately targets the current OS — narrower device matrix, full access to current SwiftUI/Observation/Concurrency features.)
- arm64 only. App Store category: Music.
- `Info.plist` must declare `UIBackgroundModes: audio`. Only add `NSMicrophoneUsageDescription` if tap-tempo-by-mic is implemented.
- Audio session: `.playback` with `[.mixWithOthers]` (must coexist with music apps and tuners).
- Xcode project has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — every type is `@MainActor` by default. The audio engine MUST opt out with explicit `actor` declaration or `nonisolated` (see Architecture below).

## Non-negotiable timing-engine constraints

The spec is unusually prescriptive about the audio path because casual choices here break the product. Honor these even if a simpler alternative looks tempting:

- **Schedule clicks with `AVAudioPlayerNode.scheduleBuffer(at:)`** against `AVAudioEngine`, using `mach_absolute_time` / `AVAudioTime` as the reference clock. Pre-schedule 4–8 beats ahead and refill on a background queue.
- **Do not use `Timer` or `DispatchSourceTimer`** for click scheduling — both drift under load. **Drift budget: < 1 ms/minute**, sustained.
- **Voice count uses pre-recorded samples**, never `AVSpeechSynthesizer` (too slow/unreliable for tight timing).
- **Visual pulse must sync to the audio clock** via `CADisplayLink` or `TimelineView` at 60fps, not an independent timer.
- **Haptics (`CoreHaptics`) must fire from the same scheduling clock** as audio, not a parallel timer.
- Playback must keep running when backgrounded, locked, or in silent mode.

## Architecture (spec §17)

- **MVVM with the iOS 17 Observation framework** (`@Observable`), not legacy `ObservableObject`.
- `MetronomeEngine` is an `actor` (NOT `@MainActor`); it owns mutable state + the attached `AudioScheduler` / `MIDIScheduler` / `MIDIReceiver` / `HapticScheduler`. View models read from it on the main actor via `await`.
- The scheduling math lives in `ClickSchedule` — pure, no AVFoundation, no time source of its own — so it's fully testable against `FakeClock` (`EngineClock` protocol). This is what enables the 316 fast unit tests.
- `AudioScheduler` is a **separate** `actor` that owns the `AVAudioEngine` + a single `AVAudioPlayerNode` and runs the refill loop. The engine pushes "schedule changed" events via `scheduleReset()`; the scheduler flushes pending buffers and refills from the new schedule. Keeping it separate from the engine means `MetronomeCore` stays buildable in environments without AVFoundation (and audio code can be swapped/mocked). `schedulingEndTime` (set via `scheduleResetWithCap`) caps how far ahead the scheduler queues clicks — used by `SongSectionPlayer` to prevent past-boundary clicks from queuing into the next section.
- `MIDIScheduler` (send) and `MIDIReceiver` (slave) are separate actors with the same attach-and-push pattern. Both are optional; engine works silently without them. `HapticScheduler` follows the same shape and caps queueing at `schedulingHorizonSeconds = 0.5s` so mode changes propagate within half a second (haptic engine has no `.interrupts` equivalent).
- `SongSectionPlayer` and `SetlistPlayer` are actors that coordinate section-by-section and song-by-song advance. `SongSectionPlayer.play(_:, onSectionsExhausted:)` accepts an optional completion callback so `SetlistPlayer` can chain into the next song without the section player tearing down the engine. Section transitions go through `MetronomeEngine.applyForSectionTransition(_:sectionMeasureCount:)` which atomically detaches the audio scheduler during `apply()`, then resets + caps in one call to eliminate Task races.
- **Persistence**: SwiftData `@Model` classes in the app target (`meter-gnome/Persistence/PersistedModels.swift`), with `SettingsStore` and `LibraryStore` as the read/write surfaces. The spec's "suggested" three-package split (Core / UI / Persistence) was **not** adopted — one package + app target was sufficient.
- **Testing strategy**: unit-test against `FakeClock` in `Tests/MetronomeCoreTests/`. No audio output is exercised in tests; drift verification at the math level only. Real-device drift test is still a manual procedure (see TODO.md).

## Spec details that drive modeling (easy to miss)

- **Tempo: 20–400 BPM in 0.1 BPM increments.** Display rounded to whole BPM by default; "precision mode" setting exposes the tenths. Don't model BPM as `Int`.
- **Time signature**: numerator 1–32, denominator ∈ {1, 2, 4, 8, 16, 32}. Custom/odd meters must be fully supported.
- **Compound-meter accent groupings** (e.g., 7/8 as 2+2+3 vs 3+2+2 vs 2+3+2) are user-editable per time signature — needs first-class modeling, not a flag.
- **Accent level is a 5-value enum**: `mute / soft / normal / loud / accent`. Per beat you also store optional sound override and ±1-octave pitch override.
- **Accent pattern presets are scoped to a specific time signature** — don't make them globally interchangeable.
- **Subdivisions** go up through septuplets plus custom 8/9. **Each subdivision level has independent volume AND optional independent sound** — shipped in v0.16.0 as `EngineSettings.subdivisionConfigs: [Subdivision: SubdivisionConfig]`. Missing keys fall through to the legacy `.soft` + parent-beat-sound default; count-in subdivisions always use the legacy default regardless.
- **Polyrhythm mode** runs two independent meters concurrently (e.g., 3 against 4), each with its own sound and volume — not a single meter with secondary accents.
- **User-imported sounds**: WAV/AIFF/CAF, **< 2 s, < 1 MB**, loaded via Files app. Enforce these limits at import.
- **Voice count assets**: pre-recorded samples for English, Spanish, French, German, Japanese × male/female variants. Plan asset loading/bundle size accordingly; design for extensibility to more languages.
- **Tap tempo**: rolling average over **last 4 taps**, reset after **2 s** of inactivity.
- **Speed trainer "random mute"**: user-set percentage in the **10–50%** range.
- **Count-in**: off / 1 / 2 / 4 measures (those exact options).
- **Latency calibration**: user-adjustable offset of **±50 ms** for Bluetooth headphone latency — a common-enough gotcha to surface in onboarding.

## Background, lifecycle, and remote control (spec §16)

- Integrate **`MPNowPlayingInfoCenter`** (show tempo + song name) and **`MPRemoteCommandCenter`** (play/pause, and next/previous in setlist mode) so lock screen / Control Center / AirPods controls work.
- Handle audio **interruptions** (calls, Siri): pause cleanly, optionally auto-resume per user setting.
- Handle **route changes**: headphone unplug → pause (Apple HIG default; don't blast the click out of the speaker).

## Accessibility (spec §15) — treat as a release gate, not polish

- Full VoiceOver labels on every control; BPM changes must be announced.
- Dynamic Type compliance, high-contrast support, Switch Control compatible.
- **Respect `UIAccessibility.isReduceMotionEnabled`** in the visual pulse — required, not optional.
- **The app must be fully usable audio-only (blind-accessible).** Don't gate features behind visual-only affordances.

## External integrations (Phase 3)

- **BLE foot pedals**: support standard BLE MIDI pedals (PageFlip Firefly, AirTurn, Donner). Configurable per-button actions: start/stop, tap tempo, next/previous song, tempo ±.
- **MIDI** via CoreMIDI: send Clock + Start/Stop/Continue over BLE / USB / Network MIDI; optionally receive Clock to slave to a DAW.
- **Ableton Link** (external SDK, MIT) for tempo sync with other Link apps on the same Wi-Fi. The spec flags this as a key competitive feature — don't drop it from Phase 3.
- **Apple Watch is a standalone target**, not just a remote: full metronome runs on the watch alone, plus a haptic-only mode for silent live use. Mirroring with iPhone uses WatchConnectivity. Complications for current BPM + quick start.

## Implementation phasing (spec §21)

Status as of 2026-05 (through v0.16.2). Don't re-do shipped work; check TODO.md before starting a Phase 2/3 item.

- **Phase 1 (MVP) — ✓ shipped:** §1 engine, §2.1–2.3 meter/subdivision (incl. per-level volume + sound config, v0.16.0), §3 accents, §4.1 synthesized sounds (real samples still pending), §6.1 tap tempo, §6.2 Italian tempo presets (tap BPM digit for picker; primary marking shown under the BPM hero), §8 visual pulse, §10.1–10.3 settings (incl. Large Display mode, v0.16.2), §16 background/interruption/route-change + Now Playing + Remote Command Center (real-device verification of AirPods double-tap + Control Center transport pending).
- **Phase 2 (practice tools) — shipped:** §5 voice count *scaffold + .beats mode* ✓, full language/gender sample matrix ✗; §7.1–7.2 songs/setlists ✓ (incl. accent pattern editor, setlist auto-advance across all 3 modes); §6.3 tempo automation — gradual ramp + step BPM + ramp loops ✓; §6.4 speed trainer — random mute + step BPM + ceiling auto-stop (v0.15.1) + reverse-on-ceiling triangle ramp (v0.15.2) ✓ ("successful loops" trigger ✗ — needs practice-stats integration); §11 practice stats ✓ (session log, today/week/month totals, per-song breakdown, CSV export; richer charts + weekly/monthly goals pending); §9 haptics ✓ (all 5 modes + per-accent intensity sliders; sharpness curve still hardcoded).
- **Phase 3 (pro) — partial:** §12.2 MIDI Clock send + receive ✓ (Settings → MIDI source picker v0.18.0; Song Position Pointer v0.19.0); §7.3 multi-section songs ✓ (per-section state, D.C. al Fine, repeats, drag-to-reorder, full setlist integration across all 3 advance modes incl. `.countdown` count-in into multi-section songs, per-section custom time-signature picker v0.24.0 — D.S./coda jumps still pending); §2.4 polyrhythm ✗; §12.1 BLE pedals, §12.3 Ableton Link, §13 Apple Watch, §14 iCloud — **user has explicitly dropped these** (TODO.md).
- **Phase 4 (polish):** §15 accessibility audit, latency tuning, edge cases — partially in place (Reduce Motion respected; full audit pending). Real percussion samples (§4.1), real voice count samples (§5), user-imported sounds (§4.2) all backlog.

## Frameworks in play

SwiftUI, AVFoundation/AVFAudio, CoreHaptics, CoreMIDI, MediaPlayer (Now Playing + Remote Command Center), WatchConnectivity, SwiftData, CloudKit, Combine (where Observation isn't enough), Accelerate (only if custom click synthesis is added), Ableton Link SDK (MIT, external).

## Explicitly out of scope (spec §20)

Visual/aesthetic design (separate from `DESIGN.md`'s system), marketing assets, monetization, server-side components, audio recording / DAW features, social/sharing. Don't invent these.

**User has also explicitly dropped** (TODO.md, "for the foreseeable future"): iCloud sync (§14), Apple Watch (§13), Ableton Link (§12.3), BLE foot pedals (§12.1). Don't suggest re-adding them without checking first.

## Design System

Always read `DESIGN.md` before making any visual or UI decision.

All font choices, colors, spacing, motion, and aesthetic direction are defined there. Do not deviate without explicit user approval. In `/qa` or `/review` mode, flag any code that doesn't match `DESIGN.md`.

North star: *stage-confident timing for live use.* The app is an *instrument's read-head*, not a phone app. JetBrains Mono for numerics, SF Pro for body, vermillion `#FF3B2C` as the only accent, dark-mode-first, no Liquid Glass.

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
