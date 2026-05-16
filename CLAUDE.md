# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status

This repo currently contains **only a functional specification** (`README.md`) — no Swift sources, no Xcode project, no build system, no git history. The first implementation task will be to scaffold the iOS project. Read `README.md` end-to-end before scaffolding; it is the source of truth for what the app must do. CLAUDE.md highlights the parts of the spec that are easy to get wrong by default.

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
- A central `MetronomeEngine` owns the `AVAudioEngine`; view models read from it.
- The audio engine runs on a **dedicated audio actor or serial dispatch queue** — explicitly **not** `@MainActor`.
- Persistence: **SwiftData** models for `Song`, `Setlist`, `SoundPreset`, `AccentPattern`, `PracticeSession`. Core Data only as fallback.
- iCloud sync (if built) goes through CloudKit via SwiftData's CloudKit integration; last-write-wins is acceptable.
- Suggested split into Swift Packages: `MetronomeCore` (engine), `MetronomeUI` (views), `MetronomePersistence` (data). Splitting early makes the timing engine unit-testable in isolation.
- **Testing strategy**: unit-test the timing engine against a **fake clock**; verify scheduled-event accuracy without producing audio.

## Spec details that drive modeling (easy to miss)

- **Tempo: 20–400 BPM in 0.1 BPM increments.** Display rounded to whole BPM by default; "precision mode" setting exposes the tenths. Don't model BPM as `Int`.
- **Time signature**: numerator 1–32, denominator ∈ {1, 2, 4, 8, 16, 32}. Custom/odd meters must be fully supported.
- **Compound-meter accent groupings** (e.g., 7/8 as 2+2+3 vs 3+2+2 vs 2+3+2) are user-editable per time signature — needs first-class modeling, not a flag.
- **Accent level is a 5-value enum**: `mute / soft / normal / loud / accent`. Per beat you also store optional sound override and ±1-octave pitch override.
- **Accent pattern presets are scoped to a specific time signature** — don't make them globally interchangeable.
- **Subdivisions** go up through septuplets plus custom 8/9. **Each subdivision level has independent volume AND optional independent sound.**
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

Build Phase 1 first; don't try to land the full spec in one pass.

- **Phase 1 (MVP):** §1 engine, §2.1–2.3 meter/subdivision, §3 accents, §4.1 built-in sounds, §6.1–6.2 tap tempo + Italian presets, basic §8 visual pulse, §10.1–10.3 settings, §16 background/lifecycle.
- **Phase 2 (practice tools):** §5 voice count, §6.3–6.4 tempo automation + speed trainer, §7.1–7.2 songs/setlists, §9 haptics, §11 stats (CSV export).
- **Phase 3 (pro):** §2.4 polyrhythm, §7.3 multi-section songs / DC al fine, §12 MIDI/Link/BLE pedals, §13 Apple Watch, §14 iCloud.
- **Phase 4 (polish):** §15 accessibility audit, latency tuning, edge cases.

## Frameworks in play

SwiftUI, AVFoundation/AVFAudio, CoreHaptics, CoreMIDI, MediaPlayer (Now Playing + Remote Command Center), WatchConnectivity, SwiftData, CloudKit, Combine (where Observation isn't enough), Accelerate (only if custom click synthesis is added), Ableton Link SDK (MIT, external).

## Explicitly out of scope (spec §20)

Visual/aesthetic design, marketing assets, monetization, server-side components, audio recording / DAW features, social/sharing. Don't invent these.

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
