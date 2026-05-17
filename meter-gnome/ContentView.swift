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
import MetronomeCore

struct ContentView: View {
    let viewModel: MetronomeViewModel
    @State private var showTimeSigPicker = false
    @State private var showSubdivisionPicker = false
    @State private var showSettings = false
    @State private var showLibrary = false
    @State private var showTempoPresets = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 280 on iPad / large landscape; 180 on iPhone portrait. A first-pass
    /// alternative to true viewport-relative scaling — DESIGN.md asks for
    /// Stage BPM to fill ~55% of viewport height, which this approximates
    /// at common form factors. Full GeometryReader-driven scaling lands
    /// when the spec §10.3 "Large display mode" setting comes online.
    private var bpmFontSize: CGFloat {
        horizontalSizeClass == .regular ? 280 : 180
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.DSColor.bgBase.ignoresSafeArea()

            // TimelineView re-evaluates the body at the animation frame rate
            // so the pulse + active beat dot + tap flash track the engine
            // clock smoothly. When isRunning is false, pulseIntensity short-
            // circuits to 0 — body still re-runs every frame but most paths
            // are no-ops.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                let now = SystemClock().now
                content(at: now)
            }

            // Top overlay row — Library (leading) and Settings (trailing),
            // balanced around the centered time signature in the content
            // stack. Both icons are small + muted so they recede during
            // performance and DESIGN.md's 5-element rule applies in spirit.
            HStack {
                libraryButton
                Spacer()
                settingsButton
            }
        }
        .preferredColorScheme(.dark)
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
        .sheet(isPresented: $showSettings) {
            SettingsView(initial: viewModel.settings) { updated in
                viewModel.setSettings(updated)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(viewModel: viewModel)
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
            showLibrary = true
        } label: {
            Image(systemName: "music.note.list")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(DS.DSColor.textMuted)
                .padding(DS.Spacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Library")
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

    @ViewBuilder
    private func content(at now: TimeInterval) -> some View {
        let pulse = viewModel.pulseIntensity(at: now, reduceMotion: reduceMotion)
        let activeBeat = viewModel.currentClick(at: now)?.beatIndex
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
                beatDotsView(activeBeat: activeBeat)
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
    /// Matching by raw rawValue against `ClickSound` so display stays
    /// in sync if a sound is renamed; arbitrary strings (future user-
    /// imported sounds, spec §4.2) render with first letter uppercased.
    private var soundPresetIndicatorText: String? {
        guard let raw = viewModel.currentSoundPreset, !raw.isEmpty else { return nil }
        if let sound = ClickSound(rawValue: raw) {
            return sound.displayName
        }
        return raw.prefix(1).uppercased() + raw.dropFirst()
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
        let alFineBadge = viewModel.isAlFineMode ? " · AL FINE" : ""
        // Only show repetition counter when the section actually has
        // repeats configured — most sections play once, no need to
        // clutter Stage with "1/1" everywhere.
        if viewModel.currentSectionRepeatTotal > 1 {
            return "\(label) · \(position) · \(viewModel.currentSectionRepetition)/\(viewModel.currentSectionRepeatTotal)\(alFineBadge)"
        }
        return "\(label) · \(position)\(alFineBadge)"
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
            Text(rampIndicatorText(for: auto))
                .font(DS.Font.label)
                .monospacedDigit()
                .foregroundStyle(DS.DSColor.accentTempo)
                .textCase(.uppercase)
                .tracking(2)
                .accessibilityLabel(rampIndicatorAccessibility(for: auto))
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
                .contentTransition(.numericText(value: viewModel.bpm.value))
                .animation(.snappy(duration: 0.15), value: viewModel.bpm.value)
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
        .animation(.snappy(duration: 0.08), value: activeBeat)
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
