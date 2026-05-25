<p align="center">
  <img src="meter-gnome/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="meter-gnome icon" width="180" />
</p>

# meter-gnome

A stage-confident iOS metronome — an *instrument's read-head*, not a phone app. Built for working musicians who need glanceable timing under stage lighting.

## Status

**v1.0.0** — feature-complete and real-device verified. Engine math + audio + MIDI + persistence + library + multi-section songs + tempo automation + speed trainer + practice stats + haptics + lock-screen integration + accessibility — all shipped per spec, except items explicitly dropped (Apple Watch, iCloud sync, BLE pedals, Ableton Link, bundled audio samples).

Per-feature breakdown: see **[docs/FEATURE_STATUS.md](docs/FEATURE_STATUS.md)**.

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

### Build the macOS app (DMG)

`meter-gnome` is a multiplatform target — the same scheme builds a native macOS app (Intel + Apple Silicon universal). To produce a distributable `.dmg` locally:

```sh
# 1. Archive the macOS app, unsigned (Tier 1 — no Developer ID needed)
xcodebuild -project meter-gnome.xcodeproj -scheme meter-gnome \
           -configuration Release \
           -destination 'generic/platform=macOS' \
           -archivePath build/meter-gnome.xcarchive \
           CODE_SIGNING_ALLOWED=NO archive

# 2. Package the .app into a drag-to-install DMG
APP="build/meter-gnome.xcarchive/Products/Applications/meter-gnome.app"
rm -rf build/dmg && mkdir -p build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "meter-gnome" -srcfolder build/dmg \
               -ov -format UDZO build/meter-gnome.dmg
```

The DMG lands at `build/meter-gnome.dmg` (everything under `build/` is gitignored).

**Unsigned-build caveat:** because Tier 1 skips code signing, Gatekeeper blocks the *first* launch ("unidentified developer"). Right-click the app → **Open** → **Open**, or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/meter-gnome.app
```

Signed + notarized DMGs (no Gatekeeper warning) are **Tier 2** — they need a Developer ID Application certificate and an App Store Connect API key, then a `codesign` → `notarytool submit` → `stapler staple` pass.

**CI:** [`.github/workflows/macos-dmg.yml`](.github/workflows/macos-dmg.yml) runs this same flow on every `v*` tag (and on demand), uploads the DMG as a workflow artifact, and attaches it to the GitHub Release.

### Run the package tests (CLI)

```sh
cd Packages/MetronomeCore
swift test
```

394 tests at the v1.0 ship — engine math, accent pattern logic, setlist + multi-section player behavior, tempo automation curves, subdivision config, polyrhythm timing, MIDI SPP parsing + position offset, practice-session aggregations (daily / weekly / BPM history), goal-clamping rules, Codable round-trips, automation-ceiling auto-stop, tap-tempo median + min-interval debounce, user-imported-sound value type. Runs in ~600ms cold / ~20ms warm; no audio or UI is exercised.

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

### Real-device drift test

The spec's < 1 ms/min drift budget applies to the full audio output path. Math-level drift is unit-tested, and the audio path is verifiable in-app from **Settings → Diagnostics → Drift Self-Test** (60-second test taps `mainMixerNode`, detects click onsets via RMS energy, regresses for measured period, reports drift in ms/min with an IOI scatter plot). No external recording equipment required.

## Layout

```
meter-gnome/                          iOS app target (SwiftUI)
  Assets.xcassets/                    App icon + accent color
  Fonts/                              JetBrains Mono (Bold / Medium / Regular)
  Persistence/                        SwiftData @Model classes + stores
  *.swift                             Views, view model, audio session coordinator

Packages/MetronomeCore/               Swift package — engine + data types + tests
  Sources/MetronomeCore/              Engine, schedule math, value types, audio/MIDI/haptic schedulers, multi-section + setlist players
  Tests/MetronomeCoreTests/           394 tests, FakeClock-driven

meter-gnome.xcodeproj/                Xcode project (objectVersion 77, synchronized groups)
```

## Docs

All project documentation lives in [`docs/`](docs/):

- **[docs/FEATURE_STATUS.md](docs/FEATURE_STATUS.md)** — spec-coverage roll-up: what's shipped, what's verified on real device, what's been deliberately dropped.
- **[docs/CLAUDE.md](docs/CLAUDE.md)** — load-bearing architectural constraints; read before changing the engine or making AI-assisted edits. (A stub at the repo root re-imports this file so Claude Code's auto-load still works.)
- **[docs/DESIGN.md](docs/DESIGN.md)** — design system; read before any visual or UI change.
- **[docs/TODO.md](docs/TODO.md)** — feature backlog and known debt.
- **[docs/AUDIO_INTEGRATION_PLAN.md](docs/AUDIO_INTEGRATION_PLAN.md)** — original audio integration plan (largely executed; kept for reference).
- **[docs/FUNCTIONAL_SPEC.md](docs/FUNCTIONAL_SPEC.md)** — original functional spec; deep reference for features not yet captured elsewhere.

## License

[MIT](LICENSE) © 2026 Aaron Watkins.
