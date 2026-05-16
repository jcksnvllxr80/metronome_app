# AVAudioEngine Integration Plan

> **Status:** Draft. Awaiting `/plan-eng-review` before any audio code lands.
>
> **Goal:** Bring sound out of the speaker. Take the pure-data scheduling layer (`ClickSchedule`, `MetronomeEngine`) and wire it to `AVAudioEngine` + `AVAudioPlayerNode` per spec §1 and CLAUDE.md's non-negotiable timing constraints.

---

## What exists today

- `MetronomeEngine` actor — `start()/stop()`, settings, BPM/time-sig/subdivision/accent-pattern mutation, count-in
- `ClickSchedule` — pure math producing `Click` values with `time: TimeInterval` (relative to `EngineClock.now`)
- `EngineClock` — protocol; `SystemClock` uses `mach_absolute_time`, `FakeClock` for tests
- `Click` — has `accent`, `soundOverride`, `pitchShift`, `isCountIn`
- 131 tests passing; iOS app builds clean

## What does NOT exist

- Any code path that produces audible output
- `AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioFile`, `AVAudioSession` references
- Sound asset files (click samples)
- Background mode / lock screen support
- Audio session interruption + route change handling

---

## Architecture changes (ranked by risk)

### 1. Audio scheduler — the load-bearing piece

A new type, **`AudioScheduler`**, that the engine owns. Responsibilities:

- Holds the `AVAudioEngine` + a single `AVAudioPlayerNode` (start simple; multi-node mixing is a later optimization)
- Maintains a **lookahead buffer**: at any moment, has 4–8 clicks already scheduled on the player node via `scheduleBuffer(at:)`
- Refills the buffer on a **background dispatch queue** (NOT the main thread; NOT the audio render thread) whenever the queue drops below the lookahead floor
- Resolves each `Click` to a concrete `AVAudioPCMBuffer` (from `SoundLibrary`, see below) at scheduling time

**Open questions** (decide in plan review):
- One `AVAudioPlayerNode` for all clicks, or separate nodes per accent level (lets us mute/unmute classes of clicks without touching the schedule)?
- How aggressive should the lookahead be? Spec says 4–8 beats; at 400 BPM that's 600–1200 ms; at 20 BPM that's 12–24 *seconds*. Maybe lookahead in seconds, not beats — say "1 second or 4 beats, whichever is greater"?

### 2. The `mach_absolute_time` ↔ `AVAudioTime.hostTime` bridge

CLAUDE.md mandates `mach_absolute_time` + `AVAudioTime` for the reference clock. The bridge:

- `AVAudioTime.hostTime` IS a `mach_absolute_time` tick value (same units).
- `SystemClock.now` converts ticks → seconds. To go back: seconds → ticks via `mach_timebase_info`.
- Add `SystemClock.audioTime(forEngineTime:)` returning an `AVAudioTime` whose `hostTime` corresponds to a given `EngineClock` time. The scheduler uses this when calling `scheduleBuffer(at:)`.

**Tested by:** unit test in `MetronomeCorePackage` covering round-trip: take `clock.now`, build an `AVAudioTime`, extract back to seconds, assert delta < 1 µs.

### 3. Sound loading — `SoundLibrary`

New type, a `MainActor` data store that maps sound names (the `String?` in `BeatConfig.soundOverride` / `Song.soundPreset`) to `AVAudioPCMBuffer` instances. On startup:

- Load Phase 1 built-in samples (spec §4.1): wood block, digital beep, cowbell, clave, hi-hat, etc. — bundled in the app target as `.wav` or `.caf` (NOT `.mp3` — compressed formats add decode latency)
- Decode each to `AVAudioPCMBuffer` once, in-memory, retained for the app's lifetime
- Provide `buffer(for name: String, accent: AccentLevel) -> AVAudioPCMBuffer` resolution

**Open questions:**
- Sample format: 44.1 kHz / 48 kHz? Apple's mixer prefers 48 kHz on iOS; samples should match to avoid re-sampling per click
- Bit depth: 16-bit Int or 32-bit Float? Float is the player node's native format; Int 16 takes half the RAM
- User-imported sounds: spec §4.2 says < 2 s, < 1 MB, WAV/AIFF/CAF — enforce at import time, store decoded buffers alongside built-ins

### 4. `AVAudioSession` — the platform layer

Per CLAUDE.md + spec §16:

- Category `.playback` with `.mixWithOthers` option (driven by `EngineSettings.mixWithOthers`)
- Active in background — requires `UIBackgroundModes: audio` in `Info.plist` (not yet set)
- **Interruption handling** (calls, Siri): observe `AVAudioSession.interruptionNotification`, pause cleanly on `.began`, optionally auto-resume on `.ended` per user setting (`EngineSettings.autoResumeAfterInterruption` — new field)
- **Route change handling**: observe `AVAudioSession.routeChangeNotification`, pause on headphone unplug (`.oldDeviceUnavailable`) per HIG

These observers live on a new `AudioSessionCoordinator` (`@MainActor`) that signals into the engine. The engine reacts via `pause()` / `resume()` (NEW methods — not the same as `stop()`, since pause preserves the schedule).

### 5. Latency offset

`EngineSettings.latencyOffsetSeconds` (already exists; ±50 ms) is applied at `scheduleBuffer(at:)` time:

- For each `Click`, the actual `hostTime` is `audioTime(forEngineTime: click.time + settings.latencyOffsetSeconds)`
- Negative offset → schedules earlier; positive → later
- Test: set offset to -0.050, verify all scheduled clicks land 50 ms early in `AVAudioTime` ticks

### 6. The visual pulse + haptic clock

The view layer can already read `MetronomeEngine.upcomingClicks(count:)` to drive its `TimelineView`. With audio wired in, the engine has a *single* time source — `mach_absolute_time` via `EngineClock` — and audio output + visual pulse + (later) haptics all consume from it. No parallel timers.

**Required to make this work cleanly:**
- The engine's `startTime` (and `audioStartTime`) must be the SAME `mach_absolute_time` instant
- The first scheduled buffer must fire at exactly `audioTime(forEngineTime: clock.now + smallLeadIn)` where `smallLeadIn` covers the audio engine's pre-roll (typically 20–50 ms — to be measured)

---

## Engine API additions

Roughly the set of new methods on `MetronomeEngine`:

```swift
// New
public func pause() async  // freezes schedule + audio; resume() picks up
public func resume() async // resume after pause or interruption
public func attach(scheduler: AudioScheduler) async  // injected from app target

// Modified
public func start(countIn: CountIn? = nil) async  // now also engages audio
public func stop() async  // also stops audio + clears scheduled buffers
```

`AudioScheduler` is a separate type the app target constructs and hands to the engine. Keeping it off the engine actor's `init` means the package stays buildable on platforms without AVFoundation (e.g. unit tests on Linux CI later).

---

## Test strategy

### Existing (must keep passing)
- All 131 `MetronomeCore` tests — they test `ClickSchedule` / `MetronomeEngine` with `FakeClock`, no audio. Continue to be the source of truth for scheduling correctness.

### New (audio-side)
- `AudioSchedulerTests` — uses `AVAudioEngine` in **manual mode** (no audio output device) to verify:
  - Buffers are scheduled at the right `hostTime`
  - Lookahead refill keeps the queue at depth 4–8 across BPM changes
  - `pause()` clears scheduled buffers; `resume()` re-schedules from `clock.now`
- `SoundLibraryTests` — verifies samples load to the right format, enforces user-import size limits
- `SystemClock.audioTime` round-trip test
- **Drift verification**: schedule 1 minute of clicks at 120 BPM in manual-mode `AVAudioEngine`, capture the rendered output, FFT-detect click onsets, assert spacing variance < 1 ms (the spec's drift budget — actually verified against real audio output, not just math)

### Manual smoke test
- Build to a real device (simulator audio timing is unreliable)
- Run 5 minutes at 120 BPM with metronome unattended; confirm no audible drift against a hardware metronome

---

## Phasing — ship audio in 3 sub-commits, not one

### Sub-commit A: Plumbing only (no sound yet)
- `SystemClock.audioTime(forEngineTime:)` + tests
- Empty `AudioScheduler` shell + `attach(scheduler:)` engine method
- `Info.plist` updates (`UIBackgroundModes: audio`)
- `AVAudioSession` configuration (start, configure category, activate)
- No buffers scheduled; no sound. Build still green.

### Sub-commit B: One click sound
- `SoundLibrary` with ONE bundled sample (`wood-block.caf` or similar)
- `AudioScheduler.refill()` actually schedules `AVAudioPCMBuffer`s
- Lookahead = 4 beats hard-coded
- `pause()` / `resume()` no-op or basic implementation
- **Audible output on a real device.** First milestone where the app makes sound.

### Sub-commit C: Polish
- Phase 1 sound library (12+ samples per spec §4.1)
- `AudioSessionCoordinator` with interruption + route-change handling
- Auto-resume setting wire-up
- Lookahead adaptive (seconds-or-beats-whichever-greater)
- Real-device drift test → numbers in `DESIGN_DECISIONS.md`

---

## Risks I'm explicitly NOT addressing in this plan

- **Polyrhythm** (spec §2.4 / Phase 3) — needs two independent player nodes + two schedules
- **MIDI sync** (§12.2 / Phase 3) — separate `CoreMIDI` integration
- **Ableton Link** (§12.3 / Phase 3) — external SDK, separate planning doc
- **Watch app** (§13 / Phase 3) — separate target, partial overlap

These are out of scope for the AVAudioEngine integration; assume Phase 1 only.

---

## What I want plan-review eyes on specifically

1. **The pause/resume model** — does freezing the schedule at `clock.now` and re-anchoring on resume produce the right "feels like it picked up where I left off" UX? Or should we snap to the next downbeat after resume?
2. **Lookahead policy** — "max of N beats or M seconds" vs "always N seconds" vs "N beats". Spec says 4–8 beats; at 20 BPM that's 12+ seconds of clicks queued, which means BPM changes have a huge perceptible latency.
3. **`AudioScheduler` location** — separate type owned by the engine actor, or extension on the engine? Separate type lets us swap it for a mock; extension is one fewer concept.
4. **Sample format** — 16-bit Int vs 32-bit Float; 44.1 vs 48 kHz. Real-world cost difference.
5. **Sub-commit B's MVP scope** — is "one sound playing on every click, no count-in audio, no pause/resume" enough to ship as a milestone, or should B include something more?
