# meter-gnome

A stage-confident iOS metronome — an *instrument's read-head*, not a phone app. Built for working musicians who need glanceable timing under stage lighting.

## Status

**Phase 1 MVP in progress.** Engine math and Stage UI are done; no audio yet.

| Layer | State |
|---|---|
| Engine math (BPM, time sig, subdivision, accents, scheduling) | Built — 131/131 tests passing, drift < 1 ms/min verified |
| Stage UI (BPM hero, beat pulse, beat dots, tap tempo, time-sig picker) | Built — runs in simulator |
| Songs, Setlists, Settings, CountIn (data layer) | Built |
| Audio output | **Not wired** — plan in [AUDIO_INTEGRATION_PLAN.md](AUDIO_INTEGRATION_PLAN.md) |
| Persistence (SwiftData) | Not started |
| Sounds, haptics, background mode, lock screen | Not started |
| MIDI, BLE pedals, Ableton Link, Apple Watch | Phase 3 |

## Build & run

```sh
# Run the iOS app target
open meter-gnome.xcodeproj    # in Xcode, then ⌘R

# Run the engine package tests from CLI
cd Packages/MetronomeCore && swift test
```

Requires Xcode 26.5+ and iOS 26.5+ simulator/device.

## Layout

```
meter-gnome/                          iOS app target (SwiftUI)
Packages/MetronomeCore/               Swift package — engine + data types
meter-gnome.xcodeproj/                Xcode project
```

## Docs

- **[CLAUDE.md](CLAUDE.md)** — load-bearing architectural constraints; read before changing the engine or making AI-assisted edits.
- **[DESIGN.md](DESIGN.md)** — design system; read before any visual or UI change.
- **[AUDIO_INTEGRATION_PLAN.md](AUDIO_INTEGRATION_PLAN.md)** — draft plan for wiring AVAudioEngine; awaiting plan review before audio code lands.
- **[FUNCTIONAL_SPEC.md](FUNCTIONAL_SPEC.md)** — original functional spec; deep reference for features not yet captured elsewhere (sound library, voice count, MIDI, etc.).
