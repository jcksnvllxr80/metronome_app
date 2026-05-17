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
Each section carries its own complete state: name, BPM, time signature, subdivision, measure count, accent pattern, sound preset, repeat count, end-action, Fine marker. Editor exposes all inline. Playback auto-advances on measure boundaries, loops within a section per its repeat count, and honors D.C. al Fine (jumps back to section 0 and stops at the next section marked Fine). Stage indicator shows current section + position + repetition + AL FINE badge when applicable. Drag-to-reorder, duplicate-section. Still backlog:
- D.S. (Dal Segno) / coda jumps — like D.C. al Fine but with a "segno" mark replacing section 0 as the jump target, plus mid-pass jumps to a coda destination. Needs more UI surface than v1.
- Full time-signature picker per section (current inline menu covers 8 common ones; exotic meters like 11/8 still require setting at the song level before enabling sections)
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

### ~~Haptic "fast double-bass-pedal buzz" regardless of mode~~ — fixed in v0.13.6 (device-confirmed)
Three theories before the actual fix landed:
- v0.13.4: pass `max(0, click.time - clock.now)` to `start(atTime:)` instead of `CHHapticTimeImmediate`. No effect.
- v0.13.5: retain players in an `inFlightPlayers` array until past their fire time. No effect on the buzz but defensive — kept.
- v0.13.6 (the fix): `CHHapticPatternPlayer.start(atTime:)` takes an ABSOLUTE time in the haptic engine's timebase, not a relative offset. Anchor at `hapticEngine.currentTime + offsetFromNow` instead.

### ~~Haptic mode changes don't take effect until engine restart~~ — fixed in v0.13.7 (device-confirmed)
Surfaced after v0.13.6 landed correct haptic timing. Root cause: the refill loop scheduled new haptics into the haptic engine every 50 ms, advancing `lastScheduledTime` by ~4 clicks per pass. At slow tempos and a few seconds of runtime, the engine could have dozens of haptics queued internally — and those queued events fire at their scheduled time even after a mode change. Result: mode change took effect only after the queue fully drained, which for a running session was essentially "never until you stop." Fix: cap scheduling at `schedulingHorizonSeconds` (0.5 s ahead). Refills early-return when `lastScheduledTime > now + 0.5`; mode changes propagate within that window.

### ~~Audio dropout on tempo change while running~~ — fixed in v0.12.6 (device-confirmed)
`AVAudioPlayerNodeBufferOptions.interrupts` on the first new-schedule buffer is the documented way to preempt an in-flight queue without the recovery cost that `playerNode.reset()` was paying. No flush ceremony — the player node just switches to the new buffer. v0.12.3–v0.12.5 attempts (various combinations of reset + lead-in) all left an audible dropout; v0.12.6's .interrupts approach landed clean.

### ~~First downbeat dropped on initial play~~ — fixed in v0.12.5 (device-confirmed)
v0.12.2 set `startupLeadInSeconds` to 120 ms; v0.12.5 bumped to 250 ms to cover the larger cold-launch audio activation window. Both warm and cold-launch first downbeats now land correctly.

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
