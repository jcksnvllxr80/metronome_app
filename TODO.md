# TODO

Backlog of features and improvements, organized by priority. Phase numbers refer to [`FUNCTIONAL_SPEC.md`](FUNCTIONAL_SPEC.md) §21.

Items the user has explicitly decided NOT to pursue for the foreseeable future: iCloud sync (§14), Apple Watch (§13), Ableton Link (§12.3), BLE foot pedals (§12.1), bundled real percussion samples (§4.1 — anything that bakes audio into the app binary), bundled real voice count samples (§5 — language × gender pre-recordings shipped with the app). User-imported sounds (§4.2) is still in — those live in the user's sandbox, not the app binary.

## Priority — next session candidates

### Real-device drift test
Spec §1.1 mandates < 1 ms/minute drift. Engine math is verified via `FakeClock` unit tests, but the spec's budget applies to the full audio output path on real hardware. Load the app onto an iPhone, run for 5 minutes at 120 BPM against a hardware metronome (or a Logic Pro session set to the same tempo), record both, FFT-detect click onsets, measure spacing variance.

### Practice stats — remaining sub-features (spec §11)
Practice-session log shipped end-to-end: PracticeSession value type, SwiftData store, view-model instrumentation (records on engine stopped→running→stopped transitions, 30-sec minimum, pause/resume keeps a session continuous, captures min/max BPM across the session), Stats tab in Library with today/week/month cards + 14-day daily + 8-week weekly bar charts + per-song breakdown + CSV export + clear-history. Still backlog:
- ~~Weekly / monthly goals~~ — shipped in v0.23.0 (Settings stepper rows; Stats progress bars stack per non-zero goal)

### Tempo automation — remaining sub-features (spec §6.3)
All three §6.3 modes shipped: gradual, step, and ramp-loop. SongDetail's picker selects between them; loop mode edits a list of (BPM, measures) stages that cycle forever. Drag-to-reorder via the Edit button in the toolbar. Stage indicator renders the active mode. v0.25.0 adds a Stage quick-sheet for gradual ramps — tap the waveform icon in the top overlay (or tap the ramp indicator under the BPM hero) to set start / end BPM + duration without saving a song. Step + loop modes still live in SongDetailView; they're typically song-attached.

### Speed trainer — remaining sub-features (spec §6.4)
Random-mute mode + step BPM both shipped. Step mode lives at Song detail → Tempo Automation → Step: start BPM, increment per step, measures per step, optional ceiling, and (when a ceiling is set) a Stop / Reverse picker. Stop = default spec §6.4 behavior (engine halts at the ceiling). Reverse = triangle-wave ramp that counts back down to `startBPM` and stops at the valley. Engine auto-stops via `engine.hasReachedAutomationCeiling`, which fires at the ceiling step in .stop mode and at the valley in .reverse mode. Still backlog:
- "Successful loops" trigger — increment only after the user completes N error-free passes; needs practice-stats integration to detect "successful"

## Phase 3 backlog

### ~~Polyrhythm (spec §2.4)~~ — shipped in v0.30.0
Same-measure flavor (3-against-4, 5-against-7) — both meters share one measure boundary; the polyrhythm is N evenly-spaced pulses inside it. Engine math via `PolyrhythmConfig` + `ClickSchedule.polyClick(at:)`; audio renders through a second `AVAudioPlayerNode` with independent volume; Stage shows a secondary hollow-dot row under the primary beat dots; Settings has the engine-level default, SongDetail has a per-song override with inherit-on-nil semantics. Independent-BPM polymeter (different tempos drifting in and out of phase) is the heavier alternative and is deliberately deferred — three of the four "Phase 3" musicians I imagine practicing 3:4 want same-measure. If the polymeter use case surfaces, the natural next step is a separate Schedule with its own `bpm` field.

### Multi-section songs — remaining (spec §7.3)
Each section carries its own complete state: name, BPM, time signature, subdivision, measure count, accent pattern, sound preset, repeat count, end-action, Fine marker. Editor exposes all inline. Playback auto-advances on measure boundaries, loops within a section per its repeat count, and honors D.C. al Fine (jumps back to section 0 and stops at the next section marked Fine). Stage indicator shows current section + position + repetition + AL FINE badge when applicable. Drag-to-reorder, duplicate-section. Setlist integration: when a setlist's current song is multi-section, playback routes through `SongSectionPlayer` with a completion callback so sections auto-advance and the setlist then chains to the next song honoring all three advance modes — `.immediate` / `.countdown` (sections auto-advance after the prior song ends; `.countdown(measures: N)` now plays an N-measure count-in prelude at section 0's tempo before the multi-section song begins, matching flat-song behavior — v0.17.0) and `.pause` (engine stops with section 0's tempo loaded; pressing Play routes through `SetlistPlayer.resumeAfterPause` which engages the section player when the song is multi-section). Still backlog:
- ~~D.S. (Dal Segno) al Fine~~ — shipped in v0.26.0. SongSection.isSegno flag + SectionEndAction.dalSegnoAlFine; player scans backwards for the nearest preceding segno mark on jump, falls back to section 0 when no segno exists in the chart. Editor exposes a "Segno (D.S. jump target)" toggle alongside the existing Fine toggle.
- ~~Coda (mid-pass jump destination) + D.C./D.S. al Coda~~ — shipped in v0.27.0. SongSection.isCoda flag + SectionEndAction.daCapoAlCoda + .dalSegnoAlCoda. Player tracks alCodaMode + codaTriggerIndex; on the second pass when the trigger section reaches its natural boundary, jumps forward to the next isCoda mark. Ends naturally when no downstream coda mark exists (rather than looping forever).
- ~~Full time-signature picker per section~~ — shipped in v0.24.0 (per-row Menu now has a "Custom…" item that opens TimeSignaturePickerView, which gains a numerator stepper 1–32 + denominator picker 1/2/4/8/16/32; affects Stage time-sig picker too)

### Haptic feedback — remaining sub-features (spec §9)
All 5 modes shipped + per-accent intensity sliders. `HapticScheduler` mirrors `AudioScheduler`'s shape — same engine click stream, same refill cadence. Sharpness curve still hardcoded (it's a tactile quality, not user-facing loudness). Real device only — Simulator has no haptic engine. Still backlog:
- Real-device verification + tuning of the default intensity / sharpness curves; the current defaults are guesses

## Phase 4 polish

### Accessibility audit (spec §15)
- VoiceOver labels on every control — audited in v0.28.0; all icon-only toolbar buttons (gear/library/time-sig/subdivision/play/stop/nudge/tap/duplicate/delete) confirmed labeled. Fixed: TimeSignaturePickerView preset tiles now carry `.isSelected` trait + "currently selected" suffix; SubdivisionPickerView rows now carry `.isSelected`; SongPickerView rows now expose name + BPM + meter + selected state as a single accessibility element; AccentPatternLibraryView preset rows now announce the beat sequence (the accent dots were visual-only); LibraryView segmented control now has a "Library section" accessibility label
- Dynamic Type compliance (verify with all sizes including AccessibilityXXXL)
- `UIAccessibility.isReduceMotionEnabled` respect (done for visual pulse; audit other animations)
- High contrast support
- Switch Control compatibility
- Full audio-only operation (blind-accessible) — primary Stage + Library surfaces audited in v0.28.0; remaining sweeps: SongDetailView pickers, SettingsView toggles, StatsView charts

### ~~Real percussion samples (spec §4.1)~~ — dropped indefinitely
Would require bundling .caf / .wav samples into the app binary. User decided in v0.30.0 that's not the direction; the 4 synthesized timbres are sufficient and the import flow below covers users who want custom sounds.

### ~~Real voice count samples (spec §5)~~ — dropped indefinitely
Same reason — the language × gender × phrase matrix would balloon the app binary. The synthesized voice tones stay as the only voice-count implementation; `.subdivisions` / `.measures` / `.silentCount` modes also dropped since they only made sense with real samples.

### ~~User-imported sounds (spec §4.2)~~ — shipped in v0.31.0
Files app integration via `.fileImporter` accepting WAV / AIFF / CAF. Imports are validated (< 2 s duration, < 1 MB file size) and copied into `Documents/UserSounds/<UUID>.<ext>`. `UserSoundRegistry` actor pre-renders four per-accent buffers (soft / normal / loud / accent) with the user's volume trim baked in, so the audio refill loop pays no signal-processing cost per click. `UserSound.soundPresetKey` of the form `"user:<UUID>"` flows through the existing String-keyed `soundPreset` resolution chain in `AudioScheduler`. Sound pickers in SongDetail + AccentPatternEditView surface imports after the built-in cases; Settings → Sound → Imported Sounds is the drill-in to import / rename / retrim / delete. Engine-level `EngineSettings.clickSound` stays built-in only (it's a `ClickSound` enum) — that's a deliberate scoping decision, not a bug. Power-users who want a user sound as the engine default would do it per-song. Polyrhythm sound also stays built-in for the same reason; PolyrhythmConfig.sound is still typed `ClickSound`.

### ~~Per-song sound preset Stage indicator~~ — shipped in v0.15.3
A small "🔊 Cowbell" row now sits under the loaded-song title (and under any section indicator) whenever a song is loaded that overrides the global default sound. Renders nothing when `engine.currentSoundPreset` is nil. Uses `ClickSound.displayName` for known presets, falls through to capitalized rawValue for arbitrary strings (forward-compatible with user-imported sounds, spec §4.2). Setlist playback shows the loaded-song title via its own setlist indicator and doesn't currently surface the preset there — follow-up if it ever matters.

## Engine / audio improvements

### ~~Lookahead policy refinement~~ — capped in v0.27.2
Lookahead now clamps to `min(48, max(4, ceil(0.5s / clickPeriod)))`. Worst-case pathological combination (400 BPM + custom-9 subdivision) yields ~31 clicks, well under the cap. Real-device profiling still pending if we ever want to tune the lower 0.5s floor or the 48-click ceiling.

### ~~MIDI Song Position Pointer support (spec §12.2)~~ — shipped in v0.19.0
Receiver parses 0xF2 + LSB + MSB messages with a state machine that lets real-time status bytes interleave per MIDI spec. SPP value is stored as `pendingMIDIBeats: UInt16?` and consumed by the next 0xFA Start by passing `positionOffsetSeconds = beats * bpm.beatPeriod / 4` to `engine.start`. The schedule's `startTime` shifts backward by that offset so click(0) lands in the past and the first future click maps to the song-time position the DAW asked for — measure / beat / subdivision indexing follows naturally. Continue (0xFB) intentionally ignores pending SPP per common-master convention. Mid-song position offset + count-in are mutually exclusive (count-in is suppressed when offset > 0).

### ~~MIDI source picker (UI)~~ — shipped in v0.18.0
Settings → MIDI now shows a "Source" picker when "Listen for MIDI Clock" is on. Default "All Sources" preserves the legacy receiver behavior (listen to every external source); selecting a specific name restricts the receiver to only that source. Live source list pulled from CoreMIDI on sheet appear; missing-but-selected sources render as "Name (offline)" so a previously-paired DAW that disconnected doesn't quietly lose the selection. New `EngineSettings.midiReceiveSourceName: String?` persisted via SwiftData; `MIDIReceiver.setSelectedSource(name:)` bounces the connection in place when the selection changes mid-session.

### ~~Subdivision config~~ (spec §2.3) — shipped in v0.16.0
`SubdivisionConfig` (accent + optional `soundOverride`) lives on `EngineSettings.subdivisionConfigs: [Subdivision: SubdivisionConfig]`. Each level keeps its own choice, so flipping between .eighth and .triplet preserves per-level config. ClickSchedule pulls the entry for the active subdivision at rebuild time and applies it to non-zero-index sub clicks; missing entries fall through to the legacy `.soft` + parent-beat-sound behavior, so existing users see no change until they touch Settings → Subdivisions. Count-in subdivisions always stay on the legacy default. UI: Settings → Subdivisions → drill-in list with volume + sound pickers per level, plus a "Reset to Default" action that removes the entry from the map.

## UI gaps

### iPad-specific layouts
- Size-class branching covers the basics: BPM scales viewport-relative via GeometryReader (v0.32.0) instead of the legacy four-way static table. Large display mode (spec §10.3) shipped in v0.16.2; in v0.32.0 it switched from fixed point sizes to bumped width/height factors fed into the same GeometryReader formula.
- ~~iPad two-column layout (Stage left + Library right)~~ — shipped in v0.29.0; refined v0.32.0 with a collapsible dock. Library button on Stage now doubles as a dock toggle on iPad (collapse → reclaim full width for Stage; expand → re-dock the panel). Preference persists via `@AppStorage("ipadLibraryDocked")`.
- ~~Viewport-relative scaling via GeometryReader~~ — shipped in v0.32.0. `bpmFontSize` computes from the Stage column's actual size: `min(height * heightFactor, width / widthDivisor)`, with floor/ceiling clamps. Replaces the static (size class × large-display) lookup table. Adapts cleanly to iPad split (~414pt column), iPad full-screen with dock collapsed (~1194pt column), iPhone, and any future external display.
- Backlog: resizable splitter (currently the Library dock is fixed at 420pt; users with very wide iPads might want a wider sidebar). Skipping unless asked.

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
