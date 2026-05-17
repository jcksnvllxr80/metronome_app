//
//  ContentView.swift
//  meter-gnome
//
//  Stage view per DESIGN.md — composition-first poster with BPM as the
//  read-head, time signature above, beat indicator and play/stop + ±
//  controls + tap tempo below. Five top-level elements total. No audio yet
//  — the engine schedules clicks internally but doesn't produce sound. The
//  visual pulse drives off the engine's clock so it correlates exactly with
//  what audio will play once wired.
//

import SwiftUI
import UIKit
import MetronomeCore

struct ContentView: View {
    let viewModel: MetronomeViewModel
    @State private var showTimeSigPicker = false
    @State private var showSubdivisionPicker = false
    @State private var showSettings = false
    @State private var showLibrary = false
    /// Stage-quick-action sheet for tempo automation (spec §6.3). Tap
    /// the rampIndicator (or the long-press hint when no automation is
    /// active) to open.
    @State private var showTempoAutomation = false
    @State private var showTempoPresets = false
    /// Last BPM announced via UIAccessibility — used to debounce so a
    /// running ramp doesn't spam VoiceOver. We only announce when
    /// |Δ| ≥ announceBPMThreshold AND no announcement has fired in
    /// the last announceMinIntervalSeconds. Spec §15 mandates that
    /// BPM changes are announced.
    @State private var lastAnnouncedBPMDisplay: Int = -1
    @State private var lastAnnounceAt: TimeInterval = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Persisted preference for the iPad Library dock. `true` (default)
    /// shows Library beside the Stage; `false` collapses to a Stage-
    /// only layout where the libraryButton reappears to surface the
    /// sheet path. Persists via @AppStorage so the user's choice
    /// survives relaunch without round-tripping through EngineSettings.
    @AppStorage("ipadLibraryDocked") private var libraryDocked: Bool = true

    private static let announceBPMThreshold = 5
    private static let announceMinIntervalSeconds: TimeInterval = 0.5

    /// Stage column's available size, captured by a GeometryReader at
    /// `stageBody`'s root. Drives viewport-relative scaling of the BPM
    /// hero — replaces the v0.29.x four-way static font-size table so
    /// iPad split, iPad full-screen, iPhone, and Large Display mode
    /// all derive a sensible hero size without separate branches.
    @State private var stageSize: CGSize = .zero

    /// Stage BPM hero font size, computed from the Stage column's
    /// actual width + height per DESIGN.md's ~55% of viewport heuristic.
    /// Picks the more constraining of two limits so the digit never
    /// overflows horizontally OR pushes the controls off the bottom:
    ///   - height-based: `height * heightFactor`
    ///   - width-based:  `width / widthDivisor`  (JetBrains Mono Bold
    ///     digits are roughly 0.55em wide, so 3 digits at width
    ///     `W` fit a font size up to `W / 1.65`)
    /// Large-display mode (spec §10.3) bumps both factors so the
    /// digit reads from across the room when the device is on a stand.
    /// Falls back to a sensible iPhone-portrait default before the
    /// GeometryReader fires its first measurement (stageSize == .zero).
    private var bpmFontSize: CGFloat {
        guard stageSize.width > 0, stageSize.height > 0 else { return 180 }
        let isLarge = viewModel.settings.largeDisplayMode
        let heightFactor: CGFloat = isLarge ? 0.62 : 0.45
        let widthDivisor: CGFloat = isLarge ? 1.25 : 1.70
        let byHeight = stageSize.height * heightFactor
        let byWidth = stageSize.width / widthDivisor
        // Floor + ceiling so degenerate viewport sizes (zero-width
        // during layout passes, gigantic external display) don't
        // produce comically small or large digits.
        return min(max(min(byHeight, byWidth), 120), 520)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular && libraryDocked {
                // iPad split: Stage on the left, Library docked on the
                // right. Library stays put when songs load — `dismiss()`
                // calls inside LibraryView become no-ops because the
                // view isn't in a presentation context. The Stage panel
                // owns the sheets for time-sig / subdivision / etc. so
                // they continue to look like Stage modals.
                HStack(spacing: 0) {
                    stageBody
                        .frame(maxWidth: .infinity)
                    Divider()
                        .background(DS.DSColor.bgElevated)
                    LibraryView(viewModel: viewModel)
                        .frame(width: librarySidebarWidth)
                }
                .background(DS.DSColor.bgBase.ignoresSafeArea())
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: libraryDocked)
            } else {
                // Stage-only layout: iPhone always, iPad when the user
                // collapsed the dock. Library still reachable via the
                // sheet flow that appears in the top-left button.
                stageBody
                    .sheet(isPresented: $showLibrary) {
                        LibraryView(viewModel: viewModel)
                            .presentationDetents([.large])
                    }
                    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: libraryDocked)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.bpm) { _, newBPM in
            announceBPMIfNeeded(newBPM)
        }
        .onChange(of: viewModel.isRunning) { _, isRunning in
            announceRunStateIfNeeded(isRunning)
        }
    }

    /// Width of the docked library panel on iPad. ~420pt fits a tab
    /// picker (320pt) plus comfortable padding, leaves the BPM hero
    /// the dominant element on the Stage side at landscape and most
    /// portrait sizes.
    private var librarySidebarWidth: CGFloat { 420 }

    /// Stage content (BPM hero, transport, top overlay). On iPhone this
    /// is the whole app body; on iPad it's the left column of the
    /// split layout. All Stage-owned sheets attach here so they
    /// surface from the Stage column on iPad rather than from the
    /// whole window.
    private var stageBody: some View {
        ZStack(alignment: .top) {
            DS.DSColor.bgBase.ignoresSafeArea()

            // GeometryReader captures the Stage column's actual size
            // so `bpmFontSize` can compute a viewport-relative hero
            // size — replaces the four-way static table that didn't
            // know about iPad-split column widths or external displays.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { stageSize = proxy.size }
                    .onChange(of: proxy.size) { _, newSize in
                        stageSize = newSize
                    }
            }

            // TimelineView re-evaluates the body at the animation frame rate
            // so the pulse + active beat dot + tap flash track the engine
            // clock smoothly. When isRunning is false, pulseIntensity short-
            // circuits to 0 — body still re-runs every frame but most paths
            // are no-ops.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                let now = SystemClock().now
                content(at: now)
            }

            // Top overlay row — Library (leading), Settings (trailing),
            // and a small Ramp (tempo automation quick-sheet) button next
            // to Settings. Icons stay small + muted so they recede during
            // performance and DESIGN.md's 5-element rule applies in spirit.
            // On iPad, the library button doubles as the dock toggle when
            // the Library is currently docked — the dock-aware version
            // collapses the sidebar instead of presenting a sheet.
            HStack {
                if horizontalSizeClass != .regular || !libraryDocked {
                    libraryButton
                } else {
                    libraryDockToggle
                }
                Spacer()
                tempoAutomationButton
                settingsButton
            }
        }
        .sheet(isPresented: $showTimeSigPicker) {
            TimeSignaturePickerView(current: viewModel.timeSignature) { selected in
                viewModel.setTimeSignature(selected)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSubdivisionPicker) {
            SubdivisionPickerView(current: viewModel.subdivision) { selected in
                viewModel.setSubdivision(selected)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTempoAutomation) {
            TempoAutomationQuickView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                initial: viewModel.settings,
                loadMIDISources: { await viewModel.availableMIDISources() },
                userSoundsViewModel: viewModel
            ) { updated in
                viewModel.setSettings(updated)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showTempoPresets) {
            TempoMarkingPickerView(currentBPM: viewModel.bpm) { selected in
                viewModel.setBPM(selected)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var libraryButton: some View {
        Button {
            viewModel.refreshLibrary()
            // iPad in collapsed-dock mode: tapping the library button
            // re-docks the panel instead of opening the sheet, so the
            // affordance "matches" what the user collapsed away.
            // iPhone (or iPad with dock collapsed but user wants the
            // sheet) still gets the sheet path via showLibrary.
            if horizontalSizeClass == .regular {
                libraryDocked = true
            } else {
                showLibrary = true
            }
        } label: {
            Image(systemName: "music.note.list")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(DS.DSColor.textMuted)
                .padding(DS.Spacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(horizontalSizeClass == .regular ? "Show library panel" : "Library")
    }

    /// iPad-only button shown in the Stage top-overlay when the
    /// Library is currently docked. Tapping collapses the dock so
    /// the Stage takes the full width — handy when the BPM hero
    /// needs to be readable from across the room. The libraryButton
    /// then reappears as the affordance to redock.
    private var libraryDockToggle: some View {
        Button {
            libraryDocked = false
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(DS.DSColor.textMuted)
                .padding(DS.Spacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide library panel")
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(DS.DSColor.textMuted)
                .padding(DS.Spacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    /// Stage-quick-action entry to the tempo-automation sheet (spec
    /// §6.3 stage-quick-sheet variant). Icon goes vermillion when a
    /// ramp is active so the user gets a glanceable status indicator
    /// alongside the rampIndicator below the BPM hero. Tapping the
    /// rampIndicator opens the same sheet; this button is the
    /// primary entry when no automation is configured yet.
    /// Post a VoiceOver announcement when BPM crosses the change
    /// threshold and the debounce interval has elapsed. Spec §15
    /// mandates BPM-change announcements; debouncing keeps active
    /// ramps from spamming the assistive output.
    private func announceBPMIfNeeded(_ newBPM: BPM) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let display = newBPM.displayInt
        let now = SystemClock().now
        let delta = abs(display - lastAnnouncedBPMDisplay)
        guard delta >= Self.announceBPMThreshold,
              now - lastAnnounceAt >= Self.announceMinIntervalSeconds
        else { return }
        lastAnnouncedBPMDisplay = display
        lastAnnounceAt = now
        UIAccessibility.post(notification: .announcement, argument: "\(display) BPM")
    }

    /// Announce engine play/stop transitions to VoiceOver. Single
    /// event per state change — no debounce since these don't fire in
    /// bursts. Skipped when VoiceOver isn't running so non-AT users
    /// pay no cost. Spec §15.
    private func announceRunStateIfNeeded(_ isRunning: Bool) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: isRunning ? "Playing" : "Stopped"
        )
    }

    private var tempoAutomationButton: some View {
        Button {
            showTempoAutomation = true
        } label: {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(viewModel.automation != nil ? DS.DSColor.accentTempo : DS.DSColor.textMuted)
                .padding(DS.Spacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.automation != nil ? "Edit tempo ramp" : "Tempo ramp")
    }

    @ViewBuilder
    private func content(at now: TimeInterval) -> some View {
        let pulse = viewModel.pulseIntensity(at: now, reduceMotion: reduceMotion)
        let activeBeat = viewModel.currentClick(at: now)?.beatIndex
        let activePolyPulse = viewModel.currentPolyPulse(at: now)
        let tapFlash = viewModel.tapFlashIntensity(at: now)

        VStack(spacing: 0) {
            // "Now playing setlist" strip, shown only when a setlist is active.
            // Above the time signature, mono small caps so it reads as
            // metadata rather than competing with the BPM hero.
            if viewModel.playingSetlistName != nil {
                setlistIndicator
                    .padding(.top, DS.Spacing.md)
            }

            meterRow
                .padding(.top, viewModel.playingSetlistName == nil ? DS.Spacing.lg : DS.Spacing.xs)

            // Loaded-song name (standalone library load). Hidden when a
            // setlist is playing — the setlist indicator at the top already
            // shows the current song title.
            if viewModel.playingSetlistName == nil,
               viewModel.loadedSongTitle != nil {
                loadedSongIndicator
                    .padding(.top, DS.Spacing.xs)
            }

            if viewModel.automation != nil {
                rampIndicator
                    .padding(.top, DS.Spacing.xs)
            }

            Spacer()

            bpmView(pulse: pulse)

            Spacer()

            VStack(spacing: DS.Spacing.lg) {
                VStack(spacing: DS.Spacing.xs) {
                    beatDotsView(activeBeat: activeBeat)
                    if let polyPulses = viewModel.schedule?.polyrhythm?.pulses {
                        polyDotsView(
                            pulses: polyPulses,
                            activePulse: activePolyPulse
                        )
                    }
                }
                controlsView
                tapButtonView(flash: tapFlash)
            }
            .padding(.bottom, DS.Spacing.xxl)
        }
    }

    // MARK: - Setlist indicator

    private var setlistIndicator: some View {
        Button {
            viewModel.stopSetlist()
        } label: {
            VStack(spacing: DS.Spacing.xxs) {
                Text(setlistTopLine)
                    .font(DS.Font.label)
                    .foregroundStyle(DS.DSColor.textMuted)
                    .textCase(.uppercase)
                    .tracking(2)
                if let title = viewModel.playingSongTitle {
                    Text(title)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.DSColor.textPrimary)
                }
                if viewModel.isWaitingForResume {
                    Text("Tap Play to continue")
                        .font(DS.Font.monoData)
                        .foregroundStyle(DS.DSColor.accentTempo)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.DSColor.bgElevated)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Setlist: \(viewModel.playingSetlistName ?? ""), song \(viewModel.playingSongIndex + 1) of \(viewModel.playingSetlistCount). Tap to exit setlist.")
    }

    private var setlistTopLine: String {
        let name = viewModel.playingSetlistName ?? ""
        let n = viewModel.playingSongIndex + 1
        let total = viewModel.playingSetlistCount
        return "\(name) · \(n) of \(total)"
    }

    // MARK: - Loaded song indicator (standalone library load)

    @ViewBuilder
    private var loadedSongIndicator: some View {
        if let title = viewModel.loadedSongTitle {
            Button {
                viewModel.clearLoadedSong()
            } label: {
                VStack(spacing: DS.Spacing.xxs) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                        Text(title)
                    }
                    .font(DS.Font.label)
                    .foregroundStyle(DS.DSColor.textMuted)
                    .textCase(.uppercase)
                    .tracking(2)
                    if let sectionLine = sectionIndicatorText {
                        Text(sectionLine)
                            .font(DS.Font.label)
                            .foregroundStyle(DS.DSColor.accentTempo)
                            .textCase(.uppercase)
                            .tracking(2)
                    }
                    if let preset = soundPresetIndicatorText {
                        HStack(spacing: DS.Spacing.xxs) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(preset)
                        }
                        .font(DS.Font.label)
                        .foregroundStyle(DS.DSColor.textDim)
                        .textCase(.uppercase)
                        .tracking(2)
                    }
                }
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xxs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sectionAccessibilityLabel(title: title))
        }
    }

    /// Display name for the active per-song sound preset, or nil when
    /// the song is using the global default. Shown under the loaded-
    /// song indicator so the user has a visible cue that the click
    /// they're hearing came from the song's override, not Settings.
    /// Resolves the current sound preset to its display name via the
    /// view model — built-ins use `ClickSound.displayName`, user-
    /// imported sounds (spec §4.2) use their stored `name`, dangling
    /// keys fall back to "Unknown sound".
    private var soundPresetIndicatorText: String? {
        guard let raw = viewModel.currentSoundPreset, !raw.isEmpty else { return nil }
        return viewModel.displayName(forSoundPresetKey: raw)
    }

    /// "INTRO · 1/3" when a sectioned song is loaded; nil otherwise.
    /// Falls through gracefully when section name is missing (uses
    /// "Section N" instead).
    private var sectionIndicatorText: String? {
        guard viewModel.loadedSongHasSections,
              viewModel.currentSectionIndex >= 0,
              viewModel.currentSectionCount > 0
        else { return nil }
        let label = viewModel.currentSectionName ?? "Section \(viewModel.currentSectionIndex + 1)"
        let position = "\(viewModel.currentSectionIndex + 1)/\(viewModel.currentSectionCount)"
        let modeBadge: String
        if viewModel.isAlCodaMode {
            modeBadge = " · AL CODA"
        } else if viewModel.isAlFineMode {
            modeBadge = " · AL FINE"
        } else {
            modeBadge = ""
        }
        // Only show repetition counter when the section actually has
        // repeats configured — most sections play once, no need to
        // clutter Stage with "1/1" everywhere.
        if viewModel.currentSectionRepeatTotal > 1 {
            return "\(label) · \(position) · \(viewModel.currentSectionRepetition)/\(viewModel.currentSectionRepeatTotal)\(modeBadge)"
        }
        return "\(label) · \(position)\(modeBadge)"
    }

    private func sectionAccessibilityLabel(title: String) -> String {
        if let section = sectionIndicatorText {
            return "Loaded song: \(title), playing \(section). Tap to clear."
        }
        return "Loaded song: \(title). Tap to clear."
    }

    // MARK: - Ramp indicator (tempo automation, spec §6.3)

    @ViewBuilder
    private var rampIndicator: some View {
        if let auto = viewModel.automation {
            Button {
                showTempoAutomation = true
            } label: {
                Text(rampIndicatorText(for: auto))
                    .font(DS.Font.label)
                    .monospacedDigit()
                    .foregroundStyle(DS.DSColor.accentTempo)
                    .textCase(.uppercase)
                    .tracking(2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rampIndicatorAccessibility(for: auto))
            .accessibilityHint("Edit tempo ramp")
        }
    }

    private func rampIndicatorText(for auto: TempoAutomation) -> String {
        switch auto {
        case .gradual(let g):
            let durationPart: String
            switch g.duration {
            case .measures(let n): durationPart = "\(n) \(n == 1 ? "bar" : "bars")"
            case .seconds(let s): durationPart = "\(Int(s.rounded())) sec"
            }
            return "Ramp \(g.startBPM.displayInt) → \(g.endBPM.displayInt) · \(durationPart)"
        case .step(let s):
            let ceilingPart = s.ceiling.map { " → \($0.displayInt)" } ?? ""
            let plural = s.measuresPerStep == 1 ? "bar" : "bars"
            return "Step \(s.startBPM.displayInt)\(ceilingPart) · +\(Int(s.increment.rounded())) every \(s.measuresPerStep) \(plural)"
        case .loop(let l):
            let bpms = l.stages.map { "\($0.bpm.displayInt)" }.joined(separator: "→")
            return "Loop \(bpms) · \(l.stages.count) stage\(l.stages.count == 1 ? "" : "s")"
        }
    }

    private func rampIndicatorAccessibility(for auto: TempoAutomation) -> String {
        switch auto {
        case .gradual(let g):
            let direction: String
            if g.endBPM > g.startBPM { direction = "Accelerando" }
            else if g.endBPM < g.startBPM { direction = "Ritardando" }
            else { direction = "Tempo hold" }
            let durationPart: String
            switch g.duration {
            case .measures(let n): durationPart = "\(n) measure\(n == 1 ? "" : "s")"
            case .seconds(let s): durationPart = "\(Int(s.rounded())) seconds"
            }
            return "\(direction) from \(g.startBPM.displayInt) to \(g.endBPM.displayInt) BPM over \(durationPart)"
        case .step(let s):
            let ceilingPart = s.ceiling.map { ", ceiling \($0.displayInt) BPM" } ?? ""
            return "Speed trainer step mode starting at \(s.startBPM.displayInt) BPM, increasing by \(Int(s.increment.rounded())) BPM every \(s.measuresPerStep) measure\(s.measuresPerStep == 1 ? "" : "s")\(ceilingPart)"
        case .loop(let l):
            let stages = l.stages.map { "\($0.bpm.displayInt) BPM for \($0.measures) measure\($0.measures == 1 ? "" : "s")" }.joined(separator: ", then ")
            return "Tempo loop cycling through \(l.stages.count) stage\(l.stages.count == 1 ? "" : "s"): \(stages)"
        }
    }

    // MARK: - Meter row (time signature + subdivision, top)

    private var meterRow: some View {
        HStack(spacing: DS.Spacing.md) {
            timeSignatureButton
            subdivisionButton
        }
    }

    private var subdivisionButton: some View {
        // Always visible — even when .none — so the affordance is
        // discoverable. Muted color when off, accent when active.
        let isActive = viewModel.subdivision != .none
        return Button {
            showSubdivisionPicker = true
        } label: {
            Text(SubdivisionLabel.compact(viewModel.subdivision))
                .font(DS.Font.monoData)
                .monospacedDigit()
                .foregroundStyle(isActive ? DS.DSColor.accentTempo : DS.DSColor.textDim)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Subdivision, \(SubdivisionLabel.descriptive(viewModel.subdivision)). Tap to change.")
    }

    private var timeSignatureButton: some View {
        Button {
            showTimeSigPicker = true
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text("\(viewModel.timeSignature.numerator)")
                Text("/").foregroundStyle(DS.DSColor.textDim)
                Text("\(viewModel.timeSignature.denominator.rawValue)")
            }
            .font(DS.Font.display)
            .monospacedDigit()
            .foregroundStyle(DS.DSColor.textPrimary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Time signature, \(viewModel.timeSignature.numerator) over \(viewModel.timeSignature.denominator.rawValue). Tap to change.")
    }

    // MARK: - BPM hero

    private func bpmView(pulse: Double) -> some View {
        let digitColor = viewModel.isRunning
            ? DS.DSColor.textPrimary.mix(with: DS.DSColor.accentTempo, by: pulse)
            : DS.DSColor.textPrimary

        return VStack(spacing: DS.Spacing.sm) {
            Text(viewModel.bpmDisplay)
                .font(.custom("JetBrainsMono-Bold", size: bpmFontSize))
                .monospacedDigit()
                .tracking(-bpmFontSize * 0.022)  // ~ -2% per DESIGN.md
                .foregroundStyle(digitColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                // Animated digit transition fades + slides between BPM
                // values; with Reduce Motion the digit snaps. Spec §15
                // requires the engine to respect this system pref.
                .contentTransition(reduceMotion ? .identity : .numericText(value: viewModel.bpm.value))
                .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: viewModel.bpm.value)
                .accessibilityLabel("Tempo, \(viewModel.bpmDisplay) BPM")
                .accessibilityHint("Double tap for Italian tempo presets")
                .accessibilityAddTraits(.isButton)
            Text(tempoMarkingLabel)
                .font(DS.Font.label)
                .foregroundStyle(DS.DSColor.textMuted)
                .textCase(.uppercase)
                .tracking(2)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showTempoPresets = true
        }
    }

    /// "BPM" or "ALLEGRO · BPM" depending on whether the current tempo
    /// falls within an Italian preset's range. Surfaces the marking
    /// for free without using an extra Stage element.
    private var tempoMarkingLabel: String {
        if let marking = TempoMarking.primaryMarking(for: viewModel.bpm) {
            return "\(marking.name) · BPM"
        }
        return "BPM"
    }

    // MARK: - Beat dots

    private func beatDotsView(activeBeat: Int?) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(0..<viewModel.timeSignature.numerator, id: \.self) { i in
                let active = (i == activeBeat)
                let isDownbeat = (i == 0)
                Circle()
                    .fill(active ? DS.DSColor.accentTempo : DS.DSColor.textDim)
                    .frame(
                        width: isDownbeat ? 14 : 10,
                        height: isDownbeat ? 14 : 10
                    )
                    .accessibilityLabel(
                        active
                            ? "Beat \(i + 1) of \(viewModel.timeSignature.numerator), active"
                            : "Beat \(i + 1) of \(viewModel.timeSignature.numerator)"
                    )
            }
        }
        // Reduce Motion users still see the active beat change color
        // — they just don't see the 80ms ease between states.
        .animation(reduceMotion ? nil : .snappy(duration: 0.08), value: activeBeat)
    }

    /// Secondary dot row for the polyrhythm stream (spec §2.4). Rendered
    /// only when polyrhythm is active. Uses outlined / hollow dots so
    /// the primary beat row stays visually dominant — the polyrhythm is
    /// the secondary texture, not the read-head. Active pulse fills.
    private func polyDotsView(pulses: Int, activePulse: Int?) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(0..<pulses, id: \.self) { i in
                let active = (i == activePulse)
                Circle()
                    .strokeBorder(
                        active ? DS.DSColor.accentTempo : DS.DSColor.textDim,
                        lineWidth: 1.5
                    )
                    .background(
                        Circle().fill(active ? DS.DSColor.accentTempo : .clear)
                    )
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(
                        active
                            ? "Polyrhythm pulse \(i + 1) of \(pulses), active"
                            : "Polyrhythm pulse \(i + 1) of \(pulses)"
                    )
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.08), value: activePulse)
    }

    // MARK: - Controls

    private var controlsView: some View {
        HStack(spacing: DS.Spacing.xl) {
            nudgeButton(label: "minus", sign: -1)
            playStopButton
            nudgeButton(label: "plus", sign: 1)
        }
    }

    private func nudgeButton(label: String, sign: Double) -> some View {
        Button {
            viewModel.nudgeBPM(by: sign * viewModel.bpmNudgeStep)
        } label: {
            Image(systemName: label)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(DS.DSColor.textPrimary)
                .frame(width: 56, height: 56)
                .background(DS.DSColor.bgElevated, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sign < 0 ? "Decrease tempo" : "Increase tempo")
    }

    private var playStopButton: some View {
        Button {
            viewModel.togglePlay()
        } label: {
            Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(viewModel.isRunning ? DS.DSColor.bgBase : DS.DSColor.textPrimary)
                .frame(width: 88, height: 88)
                .background(
                    Circle().fill(viewModel.isRunning ? DS.DSColor.accentTempo : DS.DSColor.bgElevated)
                )
                .offset(x: viewModel.isRunning ? 0 : 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isRunning ? "Stop" : "Start")
    }

    // MARK: - Tap tempo

    private func tapButtonView(flash: Double) -> some View {
        // 150 ms vermillion flash on each tap, fading linearly. Provides the
        // "visual feedback per tap" the spec §6.1 requires.
        let bgColor = DS.DSColor.bgElevated.mix(with: DS.DSColor.accentTempo, by: flash * 0.6)
        let textColor = DS.DSColor.textMuted.mix(with: DS.DSColor.textPrimary, by: flash)

        return Button {
            viewModel.tap()
        } label: {
            Text("TAP")
                .font(DS.Font.label)
                .tracking(2)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .background(bgColor, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Spacing.xxl)
        .accessibilityLabel("Tap tempo")
    }
}

#Preview {
    ContentView(viewModel: MetronomeViewModel())
}
