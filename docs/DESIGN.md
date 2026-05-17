# Design System — Metronome App

> **The one memorable thing:** *stage-confident timing for live use.*
> Every visual decision serves a musician glancing at a phone (or watch, or pedal) from 2 meters away under stage lighting, often with peripheral vision, while playing.
>
> **The metaphor:** this is an *instrument's read-head* — like a Boss tuner pedal, a Korg/Yamaha hardware metronome's red tempo LED, or a Teenage Engineering OP-1 display — not a phone app. Hire a gear designer, not an iOS designer.

---

## Product Context

- **What this is:** an iOS 17+ metronome with depth — polyrhythm, BLE foot pedals, MIDI Clock + Ableton Link, Apple Watch with haptic-only mode, voice count, latency calibration, full audio-only accessibility.
- **Who it's for:** working musicians and serious students. Drummers, guitarists, pianists, ensemble players. Practice, teaching, and **live performance**.
- **Space:** iOS App Store > Music. Competitors: Soundbrenner (The Metronome), Pro Metronome, Tempo (Frozenape), PolyNome, Metron, ONYX.
- **Project type:** iOS mobile app + watchOS companion. SwiftUI, iOS 17+, dark-mode-first.
- **Anti-positioning:** *not* a casual / toy / beginner metronome. The feature list (DC al fine, polyrhythm, MIDI slave) is for users who already know what those mean.

## Aesthetic Direction

- **Direction:** **Instrument-Brutalist.** Raw, gear-like, precision-grade. Looks like equipment.
- **Decoration level:** **Minimal.** Typography and color do the work. The beat pulse *is* the decoration.
- **Mood:** Composed under pressure. Confident, not cute. Calm in motion. The kind of UI you'd trust at minute 50 of a 60-minute set.
- **What we are deliberately NOT:**
  - iOS 26 Liquid Glass (Soundbrenner's direction — beautiful but unreadable across a stage)
  - User-skinnable colors (Tempo's direction — no design opinion = generic in screenshots)
  - Visual flash-everything (Pro Metronome's direction — busy, distracting)
  - Inter as the primary font (the "I gave up on typography" signal everyone in the category has converged on)

## Typography

- **Hero / numeric read-out — `JetBrains Mono` Bold (700), tabular-nums**
  BPM. Time-signature digits. Beat counter. Session timer. Latency offset. Anything that's a number. Monospace prevents digits from "dancing" as values change; tabular-nums is non-negotiable.
- **Body / UI — `SF Pro` (system)**
  All labels, list rows, button text, settings copy. Apple's system font; Dynamic Type for free. Don't waste budget on a body font no one reads twice.
- **Tab labels + small data — `JetBrains Mono` Regular/Medium**
  Reuses the hero font at smaller sizes to keep the "instrument readout" voice consistent.

### Font scale (SwiftUI `.font` values)

| Token | Font + weight | Size | Use |
|---|---|---|---|
| `bpm.hero` | JetBrains Mono Bold | 220pt | Stage view BPM (the read-head) |
| `bpm.normal` | JetBrains Mono Bold | 96pt | Practice view BPM |
| `display` | JetBrains Mono Medium | 32pt | Stage view time signature, song-title-as-display |
| `headline` | SF Pro Semibold | 22pt | Section headers in Practice/Library |
| `body` | SF Pro Regular | 17pt | Default body text |
| `label` | SF Pro Medium | 13pt | List row labels, UI controls |
| `mono.data` | JetBrains Mono Regular | 13pt | MIDI channel, latency in ms, BLE pedal name |

All numeric tokens (`bpm.*`, `mono.data`) use `.monospacedDigit()` modifier in SwiftUI.

**Tracking:** `bpm.hero` uses ~-2% letterspacing (`.tracking(-4.4)` at 220pt). Body text uses default.

### Font loading (iOS specifics)

- Bundle `JetBrainsMono-Bold.ttf`, `JetBrainsMono-Medium.ttf`, `JetBrainsMono-Regular.ttf` in the app target.
- Register in `Info.plist` under `UIAppFonts`:
  ```xml
  <key>UIAppFonts</key>
  <array>
    <string>JetBrainsMono-Bold.ttf</string>
    <string>JetBrainsMono-Medium.ttf</string>
    <string>JetBrainsMono-Regular.ttf</string>
  </array>
  ```
- Reference by PostScript name in SwiftUI: `.font(.custom("JetBrainsMono-Bold", size: 220))`.
- License: Apache 2.0 (free for commercial use). Bundle size impact: ~600KB total. Acceptable.

**Font blacklist for this project:** Inter, Roboto, Space Grotesk, Helvetica, Arial, Open Sans, Lato, Montserrat, Poppins. Do not introduce a third typeface without explicit user approval.

## Color

- **Approach:** Restrained, hardware-inspired. One chromatic accent. Everything else is grayscale.
- **Dark mode is primary.** Light mode exists for daytime practice but is not the hero state.

### Asset catalog tokens (`Assets.xcassets/Colors/`)

Define each as a named Color asset with light + dark variants. Reference via `Color("bg.base")` in SwiftUI, or as `UIColor(named: "bg.base")` in UIKit interop.

| Token | Dark (default) | Light (fallback) | Use |
|---|---|---|---|
| `bg.base` | `#0A0B0E` | `#FAFAF8` | Background. Near-black with slight warmth — less harsh than pure black in dim venues. |
| `bg.elevated` | `#15171C` | `#FFFFFF` | Cards, sheets, list rows. **No translucency, no `.ultraThinMaterial`.** |
| `bg.recessed` | `#06070A` | `#F0EFEB` | Inset wells, slider tracks, input field backgrounds. |
| `text.primary` | `#F4EFE6` | `#1A1B1F` | Headlines, BPM digit (off-beat), primary labels. Warm off-white — vintage gear display cream. |
| `text.muted` | `#7A7F8A` | `#6A6E76` | Units ("BPM"), secondary labels, disabled state. |
| `text.dim` | `#3D424B` | `#B8BAC0` | Tertiary labels, placeholder text, separators. |
| `accent.tempo` | `#FF3B2C` | `#E0321F` | **The accent.** Beat pulse, play state, BPM digit on active beat. Vermillion red — borrowed from hardware tempo LEDs. |
| `semantic.ok` | `#67D391` | `#3B9F5C` | Connected state (Watch / BLE pedal / MIDI). Rare. |
| `semantic.warn` | `#FFB23F` | `#D88B1F` | Low battery, latency calibration off, drift warnings. |

### Color rules

1. **`accent.tempo` is ONLY for tempo-related state.** The beat pulse. The play button. The BPM digit on the active beat. Nothing else. No red "delete" buttons, no red error text — destructive states use `text.dim` + icons.
2. **No gradients.** Anywhere.
3. **No `.ultraThinMaterial` / `.regularMaterial`.** The entire app is opaque. Glass blurs the read-head metaphor (literally).
4. **Light mode is a translation, not a reinvention.** Same structure, inverted brightness, same vermillion accent. Build it as a fallback, design and review in dark.

## Spacing

- **Base unit:** 4pt
- **Density:** Comfortable on Practice, spacious on Stage.
- **Scale:** `2, 4, 8, 12, 16, 24, 32, 48, 64, 96, 128` — power-of-2-ish, easy mental math.
- **SwiftUI usage:** `.padding(8)`, `.padding(.horizontal, 24)`, etc. Stage view uses 32–64pt gaps; Practice view uses 8–16pt gaps; Library/Settings follows iOS conventions (16pt horizontal, 8pt vertical).

## Layout

- **Approach:** Hybrid — composition-first for Stage, grid-disciplined for Practice/Library/Settings.
- **Stage view (the live screen):** one-shot poster.
  - BPM fills ~55% of viewport height, centered.
  - Time signature + song name occupy a precise band above (top ~15%).
  - Play/stop and beat indicator fill the bottom (~25%).
  - **Five elements maximum.** Nothing else on screen.
- **Practice view:** strict 4-column grid, dense, organized. All controls visible without scrolling on a 6.1″ screen at default Dynamic Type.
- **Library / Settings:** standard `NavigationStack` + `List`, respects iOS conventions.
- **Tab bar:** 3 tabs maximum — **Play / Library / Settings**. NOT 5. NOT a customizable tab bar.
- **Max content width on iPad:** 600pt for Practice, 800pt for Library. Stage scales full-width to maximize BPM size.
- **Corner radius scale:** `4, 8, 12, 16, 9999` (full-pill). Default radius is `12` for cards, `8` for buttons, `4` for inputs.

## Motion

- **Approach:** Minimal-functional with one expressive move.
- **Standard transitions:** 200ms ease-out for sheet present, tab switch, slider settle. Use SwiftUI defaults; don't customize.
- **The one expressive move — the beat pulse:**
  - Triggered from the same `mach_absolute_time` source as audio scheduling and haptics (see CLAUDE.md → "Non-negotiable timing-engine constraints").
  - Attack: 10ms hard onset (color from `text.primary` → `accent.tempo`).
  - Decay: `(60000 / BPM) * 0.4` ms ease-out back to `text.primary`.
  - At 120 BPM that's a 200ms decay. At 60 BPM, 400ms. At 240 BPM, 100ms. Faster tempos get tighter pulses — visually matches the audio energy.
  - On Stage view: the BPM digit color pulses, plus an edge-flash on the bottom 4pt of the screen.
  - On Practice view: only the small beat indicator pulses; the BPM number stays still (avoid distraction during configuration).
- **Reduce Motion (mandatory, per spec §15 + CLAUDE.md → Accessibility):**
  - Beat pulse becomes a discrete two-frame color swap (no ramped opacity).
  - If the user pushes even further (Differentiate Without Color), pulse swaps SF Symbol weight or stroke instead of color.
  - All other transitions become instant.

## Component-level decisions

### BPM control
- Big number is the BPM. Tap and hold + drag vertically to scrub. Tap once to focus the keypad. ±1 / ±5 buttons flank it on Practice view (gone on Stage).
- Precision mode (per spec §10.3): displays tenths beneath the integer in `mono.data` font when enabled.

### Time signature
- Numerator / denominator stacked, mono, large. Tap to edit in a sheet.
- Grouped subdivisions (per spec §2.2) shown as small dots above the digits: `• • | • • | • • •` for 7/8 as 2+2+3.

### Accent pattern editor
- Per-beat row: each beat is a tappable column showing accent level via dot size, not color.
  - mute = empty circle
  - soft = small filled dot
  - normal = medium dot
  - loud = large dot
  - accent = large dot with ring
- Color stays grayscale; the only red is the live beat indicator overlaid on top.

### Sound picker
- Vertical list of sounds with a small waveform thumbnail (drawn in `text.muted`) and the name in body font. Tap to preview.
- No icon-in-colored-circle. Just text + waveform.

### Foot pedal / MIDI / Watch status
- A single status row at the top of Settings: each connection shows a dot (`semantic.ok` or `text.dim`) + label in `mono.data` font. No fanfare when a pedal connects — a subtle haptic and the dot turning green.

## Accessibility

(Per spec §15 — release gate, not polish.)

- **Dynamic Type:** every text element uses semantic font tokens; layout reflows. The Stage view's BPM is the only exception (it's display-typography, scaled to viewport).
- **VoiceOver:** every control labeled. BPM changes announced. Beat indicator labeled "beat 2 of 4, downbeat" / "beat 3 of 4, accent."
- **Reduce Motion:** handled in Motion section above. Use `UIAccessibility.isReduceMotionEnabled` (SwiftUI: `@Environment(\.accessibilityReduceMotion)`).
- **High Contrast:** test `UIAccessibility.isDarkerSystemColorsEnabled` (SwiftUI: `@Environment(\.colorSchemeContrast)`). When `.increased`, swap `text.muted` for `text.primary` everywhere, deepen `bg.base` to `#000000`.
- **Differentiate Without Color:** when `UIAccessibility.shouldDifferentiateWithoutColor` is true, the beat pulse swaps SF Symbol weight instead of color.
- **Audio-only operation:** every primary action must be reachable and announced via VoiceOver. The Stage view must be operable without seeing the screen.

## What this design system is NOT (anti-patterns — do not do)

- Purple/violet gradients
- 3-column feature grid with icons in colored circles
- Gradient buttons as the primary CTA
- `.ultraThinMaterial` / Liquid Glass anywhere
- User-customizable color themes (we are opinionated; that's the point)
- Decorative blobs, bubbles, or "fun" illustrations
- Inter, Roboto, Helvetica, or Space Grotesk as the primary font
- Centered everything with uniform spacing
- Generic stock-photo-style hero sections (this is an app, not a marketing site)
- Bouncy / playful animations
- Per-beat color coding (use dot size, not hue)

## Decisions log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-16 | Initial design system | Created by `/design-consultation`. North star = "stage-confident timing for live use." Anchored on the instrument-read-head metaphor. |
| 2026-05-16 | JetBrains Mono as hero font | First-principles departure from the category's Inter/SF convergence. Tabular-nums + monospace match a hardware tempo readout. |
| 2026-05-16 | Vermillion `#FF3B2C` as the only accent | Borrowed from hardware tempo LEDs (Korg/Yamaha/Boss). Semantically tied to "tempo" — never used for errors/destructive. |
| 2026-05-16 | Stage view limited to 5 elements | The highest-stakes screen must be the calmest. Configure in Practice, perform from Stage. |
| 2026-05-16 | No Liquid Glass / translucent materials | Soundbrenner went there; we deliberately don't. Opaque surfaces read better at distance under stage lighting. |
