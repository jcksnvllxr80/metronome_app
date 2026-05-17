<p align="center">
  <img src="meter-gnome/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="meter-gnome icon" width="180" />
</p>

# meter-gnome

A stage-confident iOS metronome — an *instrument's read-head*, not a phone app. Built for working musicians who need glanceable timing under stage lighting.

## Status

**Phase 1 shipped; Phase 2 mostly shipped.** Audio, MIDI, persistence, library, setlist playback, accent pattern editor, tempo automation (gradual ramp), and lock-screen / AirPods control all work end-to-end.

| Layer | State |
|---|---|
| Engine math (BPM, time sig, subdivision, accents, count-in, scheduling) | ✓ Built — 194/194 tests passing, drift < 1 ms/min verified in math |
| Audio output | ✓ Synthesized click library (4 timbres) + per-beat sound + pitch + voice count placeholder |
| Stage UI (BPM hero, beat pulse, beat dots, tap tempo, time-sig + subdivision pickers, settings, library) | ✓ Live |
| Persistence (SwiftData) | ✓ Settings + songs + setlists survive launches |
| Library: songs, setlists, song detail, accent pattern editor | ✓ Full CRUD with per-beat sound + pitch overrides |
| Setlist playback (auto-advance modes) | ✓ Pause / Countdown(N) / Immediate |
| MIDI Clock send + receive (slave mode) | ✓ Virtual source "meter-gnome"; follows external Clock + Start/Stop |
| Background mode + interruption + route-change handling | ✓ Pauses cleanly on phone calls + headphone unplug |
| Now Playing + Remote Command Center | ✓ Lock-screen tempo + song title; play/pause from AirPods + Control Center; setlist prev/next |
| Tempo automation — gradual + step | ✓ Per-song picker; gradual accel/rit over measures or seconds, step BPM ±N every M bars with optional ceiling |
| Speed trainer — random mute + step | ✓ 10–50% random mute (per-session seed) + step-up BPM with optional target ceiling |
| Practice stats / session log | ✓ Library → Stats tab: today/week/month totals + per-song breakdown + CSV export. 30-sec minimum, pause-aware. |
| Real percussion samples, haptics, polyrhythm, multi-section songs, ramp-loop automation, daily goal | Backlog — see [TODO.md](TODO.md) |
| Apple Watch, iCloud sync, BLE pedals, Ableton Link | Out of scope |

## Development

### Requirements

- macOS 26+ with **Xcode 26.5 or newer**
- iOS 26.5+ deployment target (Simulator or physical device)
- Apple ID with free developer cert is enough for on-device testing
- For CLI package work: Swift 6.x (ships with Xcode)

### Open in Xcode

```sh
open meter-gnome.xcodeproj
```

The app target is `meter-gnome`. The local Swift Package `MetronomeCore` (engine math + data types) is wired in as a dependency — it shows up in the project navigator under "Package Dependencies."

### Run on Simulator

1. In Xcode, pick a simulator from the run destination menu (any iPhone 15+ recommended for the BPM-hero typography).
2. **⌘R** to build and run.

**Simulator caveats:**
- **Audio timing is unreliable** on the simulator. Click playback works for sanity-checking, but the spec's < 1 ms/min drift budget can only be verified on a real device.
- **CoreMIDI virtual sources** are flaky on simulator — `MIDIScheduler.init?()` may return nil. Audio + UI still work; just MIDI features are unavailable until you switch to a device.
- **Haptics, background audio, Now Playing controls** require a real device.

### Run on a real iPhone

1. **Plug the iPhone in** via USB-C / Lightning cable, or pair over Wi-Fi via Xcode's Devices window (Window → Devices and Simulators).
2. In Xcode, **select the device** from the run destination menu (top toolbar).
3. **Sign the build:**
   - Project navigator → `meter-gnome` project → `meter-gnome` target → **Signing & Capabilities**
   - Set **Team** to your Apple ID team (free developer accounts work)
   - Xcode will auto-generate a provisioning profile
4. **⌘R** to build and install.
5. **First run on a fresh device:** the build will install but iOS won't trust it yet. On the iPhone: **Settings → General → VPN & Device Management → [your Apple ID] → Trust**.
6. Re-launch from the home screen.

**Free-account limitation:** the build expires after **7 days**. Re-run from Xcode (⌘R) to re-sign. A paid Apple Developer account ($99/yr) removes this limit.

### Run the package tests (CLI)

```sh
cd Packages/MetronomeCore
swift test
```

194 tests at the time of writing — all engine math, accent pattern logic, setlist player behavior, Codable round-trips. Runs in ~10ms; no audio or UI is exercised.

### Run package tests inside Xcode

Pick the **MetronomeCore** scheme (not `meter-gnome`) from the scheme picker, then **⌘U**.

### Useful CLI commands

```sh
# Verify the iOS app builds without opening Xcode
xcodebuild -project meter-gnome.xcodeproj \
           -scheme meter-gnome \
           -configuration Debug \
           -sdk iphonesimulator \
           -destination 'generic/platform=iOS Simulator' \
           build

# Clean derived data when build behaves weirdly
rm -rf ~/Library/Developer/Xcode/DerivedData/meter-gnome-*

# Check what's in the built Info.plist (UIBackgroundModes, etc.)
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "meter-gnome.app" 2>/dev/null | head -1)
/usr/libexec/PlistBuddy -c "Print" "$APP/Info.plist"
```

### Testing MIDI sync

**Sending** (meter-gnome → DAW):
1. Run on a real device.
2. Settings → MIDI Sync → **Send MIDI Clock** on.
3. In a MIDI-aware app on the same device (GarageBand for iPad, Logic for iPad, AUM, drambo, etc.), set MIDI input to "meter-gnome" and tempo source to External.
4. Press Play in meter-gnome; the other app's tempo locks to meter-gnome's BPM.

**Receiving** (DAW → meter-gnome):
1. Run on a real device.
2. Settings → MIDI Sync → **Listen for MIDI Clock** on.
3. Press Play in your DAW; meter-gnome's BPM follows + transport syncs.

### Real-device drift test (not yet automated)

The spec's < 1 ms/min drift budget applies to the full audio output path. Math-level drift is unit-tested; the audio path isn't yet. To verify on hardware:

1. Run on a real device at a fixed BPM (e.g. 120) for ≥ 5 minutes.
2. Record both meter-gnome and a hardware metronome at the same tempo.
3. Align the recordings; measure spacing between detected click onsets.
4. Variance should stay under 1 ms across the 5-minute window.

Listed as a high-priority TODO in [TODO.md](TODO.md).

## Layout

```
meter-gnome/                          iOS app target (SwiftUI)
  Assets.xcassets/                    App icon + accent color
  Fonts/                              JetBrains Mono (Bold / Medium / Regular)
  Persistence/                        SwiftData @Model classes + stores
  *.swift                             Views, view model, audio session coordinator

Packages/MetronomeCore/               Swift package — engine + data types + tests
  Sources/MetronomeCore/              Engine, schedule math, value types, audio/MIDI schedulers
  Tests/MetronomeCoreTests/           194 tests, FakeClock-driven

meter-gnome.xcodeproj/                Xcode project (objectVersion 77, synchronized groups)
```

## Docs

- **[CLAUDE.md](CLAUDE.md)** — load-bearing architectural constraints; read before changing the engine or making AI-assisted edits.
- **[DESIGN.md](DESIGN.md)** — design system; read before any visual or UI change.
- **[TODO.md](TODO.md)** — feature backlog and known debt.
- **[AUDIO_INTEGRATION_PLAN.md](AUDIO_INTEGRATION_PLAN.md)** — original audio integration plan (largely executed; kept for reference).
- **[FUNCTIONAL_SPEC.md](FUNCTIONAL_SPEC.md)** — original functional spec; deep reference for features not yet captured elsewhere.

## License

[MIT](LICENSE) © 2026 Aaron Watkins.
