# TODO

Backlog of features and improvements, organized by priority. Phase numbers refer to [`FUNCTIONAL_SPEC.md`](FUNCTIONAL_SPEC.md) §21.

Items the user has explicitly decided NOT to pursue for the foreseeable future: iCloud sync (§14), Apple Watch (§13), Ableton Link (§12.3), BLE foot pedals (§12.1).

## Priority — next session candidates

### Real-device drift test
Spec §1.1 mandates < 1 ms/minute drift. Engine math is verified via `FakeClock` unit tests, but the spec's budget applies to the full audio output path on real hardware. Load the app onto an iPhone, run for 5 minutes at 120 BPM against a hardware metronome (or a Logic Pro session set to the same tempo), record both, FFT-detect click onsets, measure spacing variance.

### Practice stats / session log (spec §11)
- `PracticeSession` value type: date, duration, BPM range, songs played
- Stats screen: total time per day/week/month, per-song play count + average tempo
- Optional daily goal tracking
- CSV export
- SwiftData @Model — `PracticeSessionStore` parallels existing stores
- Engine instrumentation to write a session on start/stop

### Tempo automation — remaining sub-features (spec §6.3)
Gradual ramp shipped (per-song, accelerando/ritardando over measures or seconds) plus the Stage ramp indicator. Still backlog:
- Step change: increase by X BPM every N measures (overlaps heavily with Speed trainer; consider folding)
- Ramp loops: cycle through multiple tempo targets
- Stage-quick-sheet variant (current UI is per-song only)

### Speed trainer mode (spec §6.4)
- Start at slow BPM, increase by X every N measures or N "successful" loops
- Optional ceiling — stop or reverse on hit
- Random-mute mode: mute 10-50% of beats (user-set %)
- Pairs with practice stats (tracks "successful" attempts)

## Phase 3 backlog

### Polyrhythm (spec §2.4)
- Two independent meters running concurrently (3 against 4, 5 against 7, etc.)
- Each meter has its own BPM ratio, sound, volume
- Architecturally: two `ClickSchedule` instances, two `AVAudioPlayerNode`s in the audio scheduler
- UI: secondary BPM/meter pair, visual indicator showing both pulse streams

### Multi-section songs (spec §7.3)
- Each section: own tempo / meter / measure count (e.g. intro 16 bars @ 90, verse 32 bars @ 120)
- Optional repeat markers / DC al fine logic
- Data model: extend `Song` with optional `sections: [SongSection]?` or add `SectionedSong` peer type
- `SetlistPlayer` already handles song-to-song transitions; section-to-section would parallel that

### Haptic feedback (spec §9)
- `CoreHaptics` — `CHHapticEngine`
- Triggered from the same clock source as audio (NOT a parallel timer — CLAUDE.md mandate)
- Modes: off / downbeat only / accents only / every beat / subdivisions too
- Per-accent intensity configurable

## Phase 4 polish

### Accessibility audit (spec §15)
- VoiceOver labels on every control (partially done; verify completeness)
- Dynamic Type compliance (verify with all sizes including AccessibilityXXXL)
- `UIAccessibility.isReduceMotionEnabled` respect (done for visual pulse; audit other animations)
- High contrast support
- Switch Control compatibility
- Full audio-only operation (blind-accessible) — currently the gear/library icons + time-sig button might fail this; audit

### Italian tempo preset UI
- Data type `TempoMarking` exists with all 9 markings (Largo–Prestissimo, spec §6.2). No UI surface to use them. Could be:
  - Chips on Stage to quick-set BPM
  - Section in the BPM nudge area
  - Sheet from the BPM digit

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
- `EngineSettings.bpmPrecisionMode` is persisted but no toggle (spec §10.3 BPM precision 0.1)
- Lock screen behavior (stay on / dim / sleep) — spec §10.2
- Keep screen awake during playback — spec §10.2
- Start-on-app-launch toggle — spec §10.2
- Allow hardware volume keys to start/stop — spec §10.4
- Headphone remote button mapping — spec §10.4

### Now Playing artwork (spec §16)
`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` are wired (play/pause/toggle, next/prev in setlists, song title + BPM artist line). Still backlog: `MPMediaItemPropertyArtwork` so the lock-screen card has an icon, real-device verification of AirPods double-tap + Control Center transport.

### Accent pattern library (spec §3.2)
- Save accent patterns as named presets, scoped to time signature
- Reuse across songs ("rock 4/4" applies to many songs)
- Currently each song owns its pattern; no shared library

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
