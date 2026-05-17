# TODO

Backlog of features and improvements, organized by priority. Phase numbers refer to [`FUNCTIONAL_SPEC.md`](FUNCTIONAL_SPEC.md) §21.

Items the user has explicitly decided NOT to pursue for the foreseeable future: iCloud sync (§14), Apple Watch (§13), Ableton Link (§12.3), BLE foot pedals (§12.1).

## Priority — next session candidates

### Real-device drift test
Spec §1.1 mandates < 1 ms/minute drift. Engine math is verified via `FakeClock` unit tests, but the spec's budget applies to the full audio output path on real hardware. Load the app onto an iPhone, run for 5 minutes at 120 BPM against a hardware metronome (or a Logic Pro session set to the same tempo), record both, FFT-detect click onsets, measure spacing variance.

### Practice stats — remaining sub-features (spec §11)
Practice-session log shipped end-to-end: PracticeSession value type, SwiftData store, view-model instrumentation (records on engine stopped→running→stopped transitions, 30-sec minimum, pause/resume keeps a session continuous, captures min/max BPM across the session), Stats tab in Library with today/week/month cards + 14-day daily + 8-week weekly bar charts + per-song breakdown + CSV export + clear-history. Still backlog:
- ~~Weekly / monthly goals~~ — shipped in v0.23.0 (Settings stepper rows; Stats progress bars stack per non-zero goal)

### Tempo automation — remaining sub-features (spec §6.3)
All three §6.3 modes shipped: gradual, step, and ramp-loop. SongDetail's picker selects between them; loop mode edits a list of (BPM, measures) stages that cycle forever. Drag-to-reorder via the Edit button in the toolbar. Stage indicator renders the active mode. Still backlog:
- Stage-quick-sheet variant (current UI is per-song only)

### Speed trainer — remaining sub-features (spec §6.4)
Random-mute mode + step BPM both shipped. Step mode lives at Song detail → Tempo Automation → Step: start BPM, increment per step, measures per step, optional ceiling, and (when a ceiling is set) a Stop / Reverse picker. Stop = default spec §6.4 behavior (engine halts at the ceiling). Reverse = triangle-wave ramp that counts back down to `startBPM` and stops at the valley. Engine auto-stops via `engine.hasReachedAutomationCeiling`, which fires at the ceiling step in .stop mode and at the valley in .reverse mode. Still backlog:
- "Successful loops" trigger — increment only after the user completes N error-free passes; needs practice-stats integration to detect "successful"

## Phase 3 backlog

### Polyrhythm (spec §2.4)
- Two independent meters running concurrently (3 against 4, 5 against 7, etc.)
- Each meter has its own BPM ratio, sound, volume
- Architecturally: two `ClickSchedule` instances, two `AVAudioPlayerNode`s in the audio scheduler
- UI: secondary BPM/meter pair, visual indicator showing both pulse streams

### Multi-section songs — remaining (spec §7.3)
Each section carries its own complete state: name, BPM, time signature, subdivision, measure count, accent pattern, sound preset, repeat count, end-action, Fine marker. Editor exposes all inline. Playback auto-advances on measure boundaries, loops within a section per its repeat count, and honors D.C. al Fine (jumps back to section 0 and stops at the next section marked Fine). Stage indicator shows current section + position + repetition + AL FINE badge when applicable. Drag-to-reorder, duplicate-section. Setlist integration: when a setlist's current song is multi-section, playback routes through `SongSectionPlayer` with a completion callback so sections auto-advance and the setlist then chains to the next song honoring all three advance modes — `.immediate` / `.countdown` (sections auto-advance after the prior song ends; `.countdown(measures: N)` now plays an N-measure count-in prelude at section 0's tempo before the multi-section song begins, matching flat-song behavior — v0.17.0) and `.pause` (engine stops with section 0's tempo loaded; pressing Play routes through `SetlistPlayer.resumeAfterPause` which engages the section player when the song is multi-section). Still backlog:
- D.S. (Dal Segno) / coda jumps — like D.C. al Fine but with a "segno" mark replacing section 0 as the jump target, plus mid-pass jumps to a coda destination. Needs more UI surface than v1.
- Full time-signature picker per section (current inline menu covers 8 common ones; exotic meters like 11/8 still require setting at the song level before enabling sections)

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

### ~~Per-song sound preset Stage indicator~~ — shipped in v0.15.3
A small "🔊 Cowbell" row now sits under the loaded-song title (and under any section indicator) whenever a song is loaded that overrides the global default sound. Renders nothing when `engine.currentSoundPreset` is nil. Uses `ClickSound.displayName` for known presets, falls through to capitalized rawValue for arbitrary strings (forward-compatible with user-imported sounds, spec §4.2). Setlist playback shows the loaded-song title via its own setlist indicator and doesn't currently surface the preset there — follow-up if it ever matters.

## Engine / audio improvements

### Lookahead policy refinement (`AUDIO_INTEGRATION_PLAN.md` open question)
- Current: `max(4 clicks, ceil(0.5s / clickPeriod))`
- At low BPM with subdivisions on, lookahead can balloon. Cap at some reasonable upper bound?
- Real-device profiling needed before tuning

### ~~MIDI Song Position Pointer support (spec §12.2)~~ — shipped in v0.19.0
Receiver parses 0xF2 + LSB + MSB messages with a state machine that lets real-time status bytes interleave per MIDI spec. SPP value is stored as `pendingMIDIBeats: UInt16?` and consumed by the next 0xFA Start by passing `positionOffsetSeconds = beats * bpm.beatPeriod / 4` to `engine.start`. The schedule's `startTime` shifts backward by that offset so click(0) lands in the past and the first future click maps to the song-time position the DAW asked for — measure / beat / subdivision indexing follows naturally. Continue (0xFB) intentionally ignores pending SPP per common-master convention. Mid-song position offset + count-in are mutually exclusive (count-in is suppressed when offset > 0).

### ~~MIDI source picker (UI)~~ — shipped in v0.18.0
Settings → MIDI now shows a "Source" picker when "Listen for MIDI Clock" is on. Default "All Sources" preserves the legacy receiver behavior (listen to every external source); selecting a specific name restricts the receiver to only that source. Live source list pulled from CoreMIDI on sheet appear; missing-but-selected sources render as "Name (offline)" so a previously-paired DAW that disconnected doesn't quietly lose the selection. New `EngineSettings.midiReceiveSourceName: String?` persisted via SwiftData; `MIDIReceiver.setSelectedSource(name:)` bounces the connection in place when the selection changes mid-session.

### ~~Subdivision config~~ (spec §2.3) — shipped in v0.16.0
`SubdivisionConfig` (accent + optional `soundOverride`) lives on `EngineSettings.subdivisionConfigs: [Subdivision: SubdivisionConfig]`. Each level keeps its own choice, so flipping between .eighth and .triplet preserves per-level config. ClickSchedule pulls the entry for the active subdivision at rebuild time and applies it to non-zero-index sub clicks; missing entries fall through to the legacy `.soft` + parent-beat-sound behavior, so existing users see no change until they touch Settings → Subdivisions. Count-in subdivisions always stay on the legacy default. UI: Settings → Subdivisions → drill-in list with volume + sound pickers per level, plus a "Reset to Default" action that removes the entry from the map.

## UI gaps

### iPad-specific layouts
- Size-class branching covers the basics: BPM scales 180→280pt on `.regular`. Large display mode (spec §10.3) shipped in v0.16.2 — Settings → Display → Large Display jumps the hero to 260pt on iPhone / 440pt on iPad, persisted in `EngineSettings.largeDisplayMode`.
- Still backlog: iPad two-column layout (Stage left + Library right). Viewport-relative scaling via GeometryReader as a polish step over the four-way static table.

### Settings — UI prefs not yet exposed
- Allow hardware volume keys to start/stop — spec §10.4
- Headphone remote button mapping — spec §10.4

### Now Playing — remaining (spec §16)
`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` wired (play/pause/toggle, next/prev in setlists, song title + BPM artist line, app-icon artwork). Real-device verification of AirPods double-tap + Control Center transport still pending.

### ~~Accent pattern library — dedicated patterns-library view~~ — shipped in v0.21.0
Library now has a fourth "Patterns" tab alongside Songs / Setlists / Stats. Presets group by time signature (sorted by numerator/denominator), with rows showing the accent-dot preview at a glance. Tap to edit (reuses AccentPatternEditView via sheet; preset UUID preserved so rename + beat changes update in place). Swipe to delete. Toolbar + opens a time-sig confirmationDialog (4/4, 3/4, 6/8, 5/4, 7/8) → new preset draft. New `viewModel.updateAccentPatternPreset(_:)` wraps the upsert-by-ID path so renames don't fork the UUID.

## Open bugs (real-device testing 2026-05)

### ~~Section transitions land mid-measure, tempos sound wrong~~ — fixed in v0.14.1
After v0.14.0 shipped D.C. al Fine, device QA found section→section transitions firing early — the new section's tempo would come in before the current section's last measure completed. Root cause: `SongSectionPlayer.tick` detected the boundary by looking at `upcomingClicks(count: 1)` and checking whether the next click was the boundary downbeat. But the lookahead returns the SOONEST unplayed click, which could be hundreds of milliseconds in the future. The tick would fire the advance as soon as the boundary downbeat appeared in the lookahead, not when wall-clock time actually reached it. Result: the previous section got truncated by up to one click period, and the next section started early. Fix: switch boundary detection to time-based — compute the natural boundary time from `schedule.startTime + boundaryClickIndex * clickPeriod` and only advance once `clock.now >= boundaryTime - reanchorLeadInSeconds`. The new section's first click (at clock.now + lead-in) then lands AT the natural downbeat, not before.

### Double-click at section boundaries — multi-stage fix
- v0.14.2 tried `scheduleResetWithFlush` (playerNode.stop+play) on transition — still produced the double click on device. By the time the boundary detection fires + the apply chain runs, the OLD section's queued boundary click has often already played.
- v0.14.3 added a `schedulingEndTime` cap that `SongSectionPlayer` set after `engine.apply`. The cap correctly prevented OLD section's boundary click from ever being queued — but it also blocked the NEW section's first click, since the apply chain's reset Tasks ran with the OLD cap (= NEW section's first click hostTime). Device QA reported "tempo isn't changing in the parts" — symptom of NEW clicks not getting queued at all.
- v0.14.4: new `AudioScheduler.scheduleResetWithCap(_:)` updates the cap AND refills in a single actor-isolated call. Device QA: tempo still not respected. Hypothesis: the 5 audio reset Tasks engine.apply dispatches were still racing with our explicit call in ways that left the scheduler in a weird state.
- v0.14.5: new `MetronomeEngine.applyForSectionTransition(_:sectionMeasureCount:)` that temporarily detaches the audio scheduler during apply (so apply's reanchor chain doesn't dispatch any audio reset Tasks), then explicitly resets the audio scheduler with the new cap + new boundary as ONE atomic operation. Eliminates the Task race entirely. v0.14.6 added device-log instrumentation that confirmed the engine layer + audio scheduler ARE updating tempo correctly at every transition (logs showed click periods matching each section's BPM, scheduler.lastScheduledTime advancing in lock-step).
- v0.14.8 (current): the audio path was correct all along — the **displayed BPM number on Stage** was stuck because `MetronomeViewModel`'s polling task only called `refreshSetlistPlaybackState` + `refreshSectionPlaybackState`, never `refresh()`. Section name updated (because the section-state refresh pulled it from the player) but `viewModel.bpm` never re-read `engine.bpm`. Audio played the new tempo; the number on screen lied. Fix: include `await refresh()` in the polling tick so BPM / timeSig / subdivision all mirror the active section in real time.

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
