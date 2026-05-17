# Feature Status

Spec-coverage snapshot as of **v1.0.0**. Section numbers reference [`FUNCTIONAL_SPEC.md`](FUNCTIONAL_SPEC.md). Shipping history per-feature is captured inline in [`TODO.md`](TODO.md); this doc is the at-a-glance roll-up.

## Shipped + verified

| Spec | Feature | State |
|---|---|---|
| §1 | Engine math (BPM, time sig, subdivisions, accents, count-in, scheduling) | ✓ Math verified via 383 unit tests. §1.1 drift budget verifiable in-app via Settings → Diagnostics → Drift Self-Test (v0.34.0) — measurement-only, no auto-correction shim. |
| §2.1 | Time signatures, including odd meters (1–32 numerator, 1/2/4/8/16/32 denominator) | ✓ |
| §2.2 | Subdivisions (none through nonuplets) | ✓ |
| §2.3 | Per-subdivision-level volume + sound config | ✓ v0.16.0 |
| §2.4 | Polyrhythm (same-measure flavor: 3:4, 5:7, etc.) | ✓ v0.30.0 — engine math, second AVAudioPlayerNode, Settings + per-song override, Stage hollow-dot indicator |
| §3.1 | Per-beat accent / sound / pitch configuration | ✓ |
| §3.2 | Accent pattern preset library | ✓ |
| §4.1 | Built-in click sounds (synthesized: wood block, digital beep, cowbell, hi-hat) | ✓ — bundled real percussion samples explicitly dropped |
| §4.2 | User-imported sounds (WAV/AIFF/CAF, <2 s, <1 MB, per-sound volume trim) | ✓ v0.31.0 |
| §5 | Voice count — `.off` and `.beats` modes with synthesized tones | ✓ scaffold; bundled language samples explicitly dropped |
| §6.1 | Tap tempo (4-tap rolling average, 2 s reset) | ✓ |
| §6.2 | Italian tempo markings | ✓ |
| §6.3 | Tempo automation — gradual / step / loop | ✓ |
| §6.4 | Speed trainer — random mute + step BPM (with stop / reverse-on-ceiling) | ✓ — "successful loops" trigger explicitly dropped (no viable detection signal for a metronome app) |
| §7.1 | Songs (named bundle of metronome state) | ✓ |
| §7.2 | Setlists with three auto-advance modes (pause / countdown / immediate) | ✓ |
| §7.3 | Multi-section songs — per-section state, drag-to-reorder, D.C./D.S. al Fine, D.C./D.S. al Coda, full setlist integration | ✓ |
| §8 | Visual pulse | ✓ |
| §9 | Haptics — 5 modes, per-accent intensity, sharpness curve | ✓ real-device verified v0.32.6 (defaults felt right out of the box, no tuning needed) |
| §10.1 | Master volume, latency calibration (±50 ms), `mixWithOthers` toggle | ✓ |
| §10.2 | Auto-resume after interruption, keep-screen-awake, start-on-launch | ✓ |
| §10.3 | Large Display mode | ✓ v0.16.2 |
| §10.4 | Hardware volume keys → start/stop, headphone remote button mapping | ✓ real-device verified v0.32.5–v0.32.6 |
| §11 | Practice stats — session log, today/week/month totals, per-song breakdown, charts, CSV export, daily/weekly/monthly goals | ✓ |
| §12.2 | MIDI Clock send + receive, Song Position Pointer, source picker | ✓ |
| §15 | Accessibility audit — VoiceOver, Dynamic Type, Reduce Motion, high contrast, Switch Control, full audio-only operation | ✓ real-device verified v0.32.6 |
| §16 | Background mode, audio interruption + route-change handling, Now Playing, Remote Command Center | ✓ real-device verified v0.32.5 — critical fix was discovering `.mixWithOthers` was permanently set and never reached the audio session coordinator; now a Settings toggle defaulting OFF |
| §17 | MVVM with Observation framework, actor-isolated engine/scheduler | ✓ |
| §19 | iOS 26.5+, arm64 only, Music category | ✓ |

## Remaining

_Engineering backlog is empty._ All spec items are either shipped + verified or explicitly dropped. Operational pre-ship items (App Store screenshots, privacy policy URL, TestFlight upload, etc.) are out of scope here.

## Explicitly dropped (not coming back without checking first)

These were considered and deliberately deferred indefinitely:

| Spec | Item | Why |
|---|---|---|
| §4.1 | Bundled real percussion samples | User prefers no pre-recorded audio in the app binary. The 4 synthesized timbres are sufficient; user-imported sounds (§4.2) cover everything else. |
| §5 | Bundled real voice count samples (per-language × gender) | Same reason — would balloon the binary. `.subdivisions` / `.measures` / `.silentCount` modes also dropped since they only made sense with real samples. |
| §6.4 | Speed-trainer "successful loops" trigger | No viable signal for a metronome app: mic onset detection too fragile in real practice rooms, tap-along needs a free hand most instruments don't have, manual mark between loops breaks practice flow. The existing measure-count step trigger is the right shipping behavior. |
| §12.1 | BLE foot pedals | User dropped. |
| §12.3 | Ableton Link tempo sync | User dropped. |
| §13 | Apple Watch standalone target | User dropped. |
| §14 | iCloud sync | User dropped. |
