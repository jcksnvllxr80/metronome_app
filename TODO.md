# TODO

Backlog of features and improvements, organized by priority. Phase numbers refer to [`FUNCTIONAL_SPEC.md`](FUNCTIONAL_SPEC.md) §21.

Items the user has explicitly decided NOT to pursue for the foreseeable future: iCloud sync (§14), Apple Watch (§13), Ableton Link (§12.3), BLE foot pedals (§12.1).

## Priority — next session candidates

### Real-device drift test
Spec §1.1 mandates < 1 ms/minute drift. Engine math is verified via `FakeClock` unit tests, but the spec's budget applies to the full audio output path on real hardware. Load the app onto an iPhone, run for 5 minutes at 120 BPM against a hardware metronome (or a Logic Pro session set to the same tempo), record both, FFT-detect click onsets, measure spacing variance.

### Practice stats — remaining sub-features (spec §11)
Practice-session log shipped end-to-end: PracticeSession value type, SwiftData store, view-model instrumentation (records on engine stopped→running→stopped transitions, 30-sec minimum, pause/resume keeps a session continuous, captures min/max BPM across the session), Stats tab in Library with today/week/month cards + per-song breakdown + CSV export + clear-history. Still backlog:
- Richer charts beyond the 14-day daily-totals bar chart (cumulative trend, BPM-over-time across sessions, per-song progress)
- Weekly / monthly goals (currently only daily)

### Tempo automation — remaining sub-features (spec §6.3)
All three §6.3 modes shipped: gradual, step, and ramp-loop. SongDetail's picker selects between them; loop mode edits a list of (BPM, measures) stages that cycle forever. Drag-to-reorder via the Edit button in the toolbar. Stage indicator renders the active mode. Still backlog:
- Stage-quick-sheet variant (current UI is per-song only)

### Speed trainer — remaining sub-features (spec §6.4)
Random-mute mode + step BPM both shipped. Step mode lives at Song detail → Tempo Automation → Step: start BPM, increment per step, measures per step, optional ceiling that holds BPM constant once reached. Still backlog:
- Engine-stops-on-ceiling: when the step ceiling is hit, automatically stop playback (currently the schedule clamps BPM but the engine keeps running)
- "Reverse on ceiling" alternative — instead of stopping, count back down
- "Successful loops" trigger — increment only after the user completes N error-free passes; needs practice-stats integration to detect "successful"

## Phase 3 backlog

### Polyrhythm (spec §2.4)
- Two independent meters running concurrently (3 against 4, 5 against 7, etc.)
- Each meter has its own BPM ratio, sound, volume
- Architecturally: two `ClickSchedule` instances, two `AVAudioPlayerNode`s in the audio scheduler
- UI: secondary BPM/meter pair, visual indicator showing both pulse streams

### Multi-section songs — remaining (spec §7.3)
Core feature shipped: SongSection value type + Song.sections field + persistence + SongSectionPlayer for auto-advance + section editor in SongDetailView + Stage indicator showing current section name + position + drag-to-reorder via the Edit button. Still backlog:
- Repeat markers / DC al fine logic — repeat N times, "go back to section X" jumps
- Per-section accent pattern editing in the section editor (currently only name/BPM/measures are editable inline; accent pattern + per-section sound preset still require the song's flat pattern)
- Setlist integration — setlists currently treat multi-section songs as flat at the song's top-level BPM; auto-advance through sections inside a setlist is a follow-up

### Haptic feedback — remaining sub-features (spec §9)
All 5 modes shipped + per-accent intensity sliders. `HapticScheduler` mirrors `AudioScheduler`'s shape — same engine click stream, same refill cadence. Sharpness curve still hardcoded (it's a tactile quality, not user-facing loudness). Real device only — Simulator has no haptic engine. Still backlog:
- Real-device verification + tuning of the default intensity / sharpness curves; the current defaults are guesses

## Phase 4 polish

### Accessibility audit (spec §15)
- VoiceOver labels on every control (partially done; verify completeness)
- Dynamic Type compliance (verify with all sizes including AccessibilityXXXL)
- `UIAccessibility.isReduceMotionEnabled` respect (done for visual pulse; audit other animations)
- High contrast support
- Switch Control compatibility
- Full audio-only operation (blind-accessible) — currently the gear/library icons + time-sig button might fail this; audit

### Real percussion samples (spec §4.1)
- Replace synthesized `ClickSound` cases with bundled `.caf` or `.wav` samples
- Source CC0 / royalty-free wood block, cowbell, clave, hi-hat, etc.
- Spec lists 12+ sounds; 4 are synthesized today
- `ClickBufferGenerator` already structured to swap any case to a sample loader

### Real voice count samples (spec §5)
- Pre-recorded "one, two, three..." per language (English, Spanish, French, German, Japanese × M/F)
- Replace `ClickBufferGenerator.makeVoiceTone` with a sample loader
- Add language + gender pickers to Settings (currently hardcoded)
- Implement `.subdivisions` ("one-and-two-and"), `.measures` (announce measure number at downbeat), `.silentCount` (count first N beats of each measure) — placeholders today

### User-imported sounds (spec §4.2)
- Files app integration
- WAV / AIFF / CAF only
- Enforce: < 2 s, < 1 MB
- Per-sound volume trim
- `Song.soundPreset: String?` already accepts arbitrary names; resolver in `AudioScheduler` falls through unknown strings to settings default — when imports land, route the same field at imported-asset URLs

### Per-song sound preset UI Stage indicator
- `Song.soundPreset` is editable in SongDetailView already; on Stage there's no indication "this song is using cowbell instead of digital beep"
- Subtle label near gear icon? Or in the meter row?

## Engine / audio improvements

### Lookahead policy refinement (`AUDIO_INTEGRATION_PLAN.md` open question)
- Current: `max(4 clicks, ceil(0.5s / clickPeriod))`
- At low BPM with subdivisions on, lookahead can balloon. Cap at some reasonable upper bound?
- Real-device profiling needed before tuning

### Sound override mid-pattern doesn't trigger schedule reset
- If user opens AccentPatternEditView while engine is running and changes per-beat sounds, the engine's `setAccentPattern` re-anchors the schedule but the AudioScheduler's queued buffers reflect the OLD pattern until the queue drains. Brief audible lag.
- Fix would require coordinating per-beat data through scheduler queue management — non-trivial. Acceptable for v1.

### MIDI Song Position Pointer support (spec §12.2)
- 0xF2 message — lets meter-gnome jump to a specific position when slaved
- Current receiver ignores it

### MIDI source picker (UI)
- Receiver currently listens to ALL external sources except our own "meter-gnome" output
- For users with multiple potential masters (DAW + drum machine), need a picker

### Subdivision config (spec §2.3)
- "Each subdivision level has independent volume AND optional independent sound" — not implemented
- Today: all subdivisions are `.soft` accent with the parent beat's sound
- Future: `SubdivisionConfig` per subdivision level

## UI gaps

### iPad-specific layouts
- Current size-class branching covers the basics (BPM scales 180→280pt on `.regular`)
- Spec §10.3 "Large display mode" — huge BPM readout for stage use
- iPad could host two columns (Stage left + Library right)

### Settings — UI prefs not yet exposed
- Allow hardware volume keys to start/stop — spec §10.4
- Headphone remote button mapping — spec §10.4

### Now Playing — remaining (spec §16)
`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` wired (play/pause/toggle, next/prev in setlists, song title + BPM artist line, app-icon artwork). Real-device verification of AirPods double-tap + Control Center transport still pending.

### Accent pattern library — remaining (spec §3.2)
Named preset library shipped + starter presets (Rock 4/4, Waltz 3/4, Compound 6/8, 7/8 2+2+3, 5/4 3+2). AccentPatternEditView has a "Save as preset" button + a list of existing presets matching the current time signature (swipe to delete) + "Add starter presets" button when the library is empty. Each song still owns its own per-beat pattern; loading a preset copies its beats into the draft. Still backlog:
- Dedicated patterns-library view (browse / rename / edit standalone without going through a song)

## Open bugs (real-device testing 2026-05)

### ~~Brief audio dropout on tempo change while running~~ — attempted fix in v0.12.4
v0.12.3 tried "inline `refillOnce()` after `playerNode.reset()`" — still dropped audio on device. v0.12.4 drops the `playerNode.reset()` call entirely: leaves the existing 4-click queue playing through at the OLD tempo and queues new clicks (from the now-reanchored schedule) starting AFTER the last-scheduled time. Transition is gapless; the audible BPM lags the displayed BPM by up to one lookahead's worth (~4 clicks) before the new tempo audibly kicks in. Trade-off vs. dropout: accepted. Verify on device. If user perceives the lag as objectionable, a follow-up could shrink the lookahead in the immediate vicinity of a reset.

### ~~First downbeat dropped on initial play~~ — fixed in v0.12.2
Engine now applies `MetronomeEngine.startupLeadInSeconds` (120 ms) to the schedule anchor on `start()` and `resume()`, so the first click lands a comfortable margin in the future of the audio path's first `scheduleBuffer(at:)` call. Mid-playback re-anchors (BPM / meter / subdivision tweaks via `setBPM` etc.) keep the lead-in at 0 — the audio engine is already running and doesn't have the startup race. Verify on device after pushing.

## Known issues / debt

### Stale `meter-gnome.png` warnings
- The user has periodically dropped icon files at the project root; the screenshot-vs-icon-vs-asset workflow could use cleanup
- Currently no script enforces "no stray files at project root"

### `scheduleBuffer` deprecation warning in AudioScheduler
- Explicit `completionHandler: nil` selects the legacy sync overload (Phase 1 commit) — compiler warns
- Migration would be to use the async variant, but that would block the refill loop on completion
- Acceptable; documented in the code

### `Subdivision.rawValue` is now `String` (was originally synth-Hashable)
- Persistence-friendly but breaking for any pre-existing comparisons by ordinal
- All callers updated; future contributors should be aware
