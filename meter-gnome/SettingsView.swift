//
//  SettingsView.swift
//  meter-gnome
//
//  Sheet that surfaces the spec §10.1-10.3 settings that map to
//  EngineSettings: count-in, master volume, latency calibration, and
//  auto-resume after interruption.
//
//  Changes apply immediately — there's no "Cancel" button. The Done
//  button just dismisses. Mirroring iOS Settings convention.
//

import SwiftUI
import MetronomeCore

struct SettingsView: View {
    let initial: EngineSettings
    let onChange: (EngineSettings) -> Void
    /// Async closure that returns the current set of external MIDI
    /// source names (deduped, "meter-gnome" filtered out). Surfaces in
    /// the MIDI section's "Source" picker so users can isolate one
    /// master out of many. Empty list = "no sources visible" which
    /// the picker labels accordingly. Defaults to `{ [] }` for
    /// previews + call sites that don't have a receiver wired up.
    let loadMIDISources: () async -> [String]
    /// View model bridge for the Imported Sounds drill-in (spec §4.2).
    /// Optional so previews + tests can construct without the full
    /// app stack; the Imported Sounds row hides when nil.
    let userSoundsViewModel: MetronomeViewModel?

    @Environment(\.dismiss) private var dismiss
    @State private var settings: EngineSettings
    @State private var midiSources: [String] = []

    init(
        initial: EngineSettings,
        loadMIDISources: @escaping () async -> [String] = { [] },
        userSoundsViewModel: MetronomeViewModel? = nil,
        onChange: @escaping (EngineSettings) -> Void
    ) {
        self.initial = initial
        self.loadMIDISources = loadMIDISources
        self.userSoundsViewModel = userSoundsViewModel
        self.onChange = onChange
        self._settings = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                displaySection
                soundSection
                subdivisionSection
                polyrhythmSection
                voiceCountSection
                countInSection
                masterVolumeSection
                latencySection
                autoResumeSection
                midiSection
                randomMuteSection
                hapticSection
            }
            .scrollContentBackground(.hidden)
            .background(DS.DSColor.bgBase)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.DSColor.accentTempo)
                }
            }
            .toolbarBackground(DS.DSColor.bgBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onChange(of: settings) { _, newValue in
            onChange(newValue)
        }
    }

    // MARK: - Sections

    /// Display-only Stage preferences (spec §10.3). Currently houses
    /// the large-display toggle and the BPM precision toggle — both
    /// affect how the Stage hero renders without touching the engine.
    private var displaySection: some View {
        Section {
            Toggle("Large Display", isOn: $settings.largeDisplayMode)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
            Toggle("BPM Precision (0.1)", isOn: $settings.bpmPrecisionMode)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Display")
                .foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Large Display makes the BPM hero significantly bigger for stage use on a music stand. BPM Precision exposes the tenths digit.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var soundSection: some View {
        Section {
            Picker("Click Sound", selection: $settings.clickSound) {
                ForEach(ClickSound.allCases, id: \.self) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }
            .pickerStyle(.menu)
            .tint(DS.DSColor.accentTempo)
            .listRowBackground(DS.DSColor.bgElevated)
            // Drill-in to the imported-sounds manager (spec §4.2).
            // Engine default `clickSound` stays built-in only; user
            // imports are picked per-song. Kept here so the
            // "where do user sounds live?" question has a single
            // discoverable answer from Settings.
            if let viewModel = userSoundsViewModel {
                NavigationLink {
                    UserSoundsView(viewModel: viewModel)
                } label: {
                    HStack {
                        Text("Imported Sounds")
                            .foregroundStyle(DS.DSColor.textPrimary)
                        Spacer()
                        Text(importedSoundsSummary(for: viewModel))
                            .font(DS.Font.monoData)
                            .foregroundStyle(DS.DSColor.textMuted)
                    }
                }
                .listRowBackground(DS.DSColor.bgElevated)
            }
        } header: {
            Text("Sound")
                .foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Default click sound. Individual songs can override this in their detail view. Imported sounds (WAV, AIFF, CAF — up to 2 s and 1 MB each) are available in any song's Click Sound picker.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    /// Compact summary for the Imported Sounds nav row — "None" when
    /// nothing has been imported, otherwise count of imports.
    private func importedSoundsSummary(for vm: MetronomeViewModel) -> String {
        let n = vm.userSounds.count
        return n == 0 ? "None" : "\(n)"
    }

    /// Per-subdivision-level click config (spec §2.3). Each level
    /// (.eighth / .triplet / …) carries its own accent + sound override
    /// for the non-zero-index sub clicks. NavigationLink into a detail
    /// view keeps the Settings list scannable — most users won't dig
    /// into this and shouldn't have to scroll past 9 levels worth of
    /// pickers.
    private var subdivisionSection: some View {
        Section {
            NavigationLink {
                SubdivisionConfigList(settings: $settings)
            } label: {
                HStack {
                    Text("Subdivisions")
                    Spacer()
                    Text(subdivisionsSummaryText)
                        .font(DS.Font.monoData)
                        .foregroundStyle(DS.DSColor.textMuted)
                }
            }
            .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Subdivisions")
                .foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Adjust the volume and sound of subdivision clicks (the \"and-a\" between main beats) per level. Defaults to soft, parent-beat sound.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    /// Compact summary for the navigation-link row — "Default" when no
    /// level has been customized, otherwise count of customized levels.
    private var subdivisionsSummaryText: String {
        let n = settings.subdivisionConfigs.count
        return n == 0 ? "Default" : "\(n) custom"
    }

    // MARK: - Polyrhythm (spec §2.4)

    /// Same-measure polyrhythm — fires N evenly-spaced pulses across
    /// each primary-meter measure with its own sound + volume. The
    /// engine default; songs override per-song in their detail view.
    private var polyrhythmSection: some View {
        Section {
            Toggle("Enable Polyrhythm", isOn: polyrhythmEnabledBinding)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
            if let poly = settings.polyrhythm {
                Stepper(
                    value: polyPulsesBinding(currentValue: poly.pulses),
                    in: PolyrhythmConfig.pulsesRange,
                    step: 1
                ) {
                    HStack {
                        Text("Pulses").foregroundStyle(DS.DSColor.textPrimary)
                        Spacer()
                        Text("\(poly.pulses)")
                            .font(DS.Font.monoData)
                            .foregroundStyle(DS.DSColor.accentTempo)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Pulses, \(poly.pulses) per measure")
                }
                .listRowBackground(DS.DSColor.bgElevated)
                Picker("Sound", selection: polySoundBinding(currentValue: poly.sound)) {
                    ForEach(ClickSound.allCases, id: \.self) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
                HStack(spacing: DS.Spacing.md) {
                    Text("Volume").foregroundStyle(DS.DSColor.textPrimary)
                    Slider(value: polyVolumeBinding(currentValue: poly.volume), in: 0...1)
                        .tint(DS.DSColor.accentTempo)
                        .accessibilityLabel("Polyrhythm volume")
                    Text("\(Int((poly.volume * 100).rounded()))%")
                        .font(DS.Font.monoData)
                        .frame(width: 48, alignment: .trailing)
                        .foregroundStyle(DS.DSColor.textPrimary)
                }
                .listRowBackground(DS.DSColor.bgElevated)
            }
        } header: {
            Text("Polyrhythm").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Plays N evenly-spaced pulses against each measure of the primary meter — e.g. 3 against 4 in 4/4 time. Independent sound + volume from the main click. Songs can override this default per-song.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    /// Toggle binding — flipping on creates a default config (3 pulses,
    /// cowbell, 80% volume); flipping off nils the setting entirely.
    private var polyrhythmEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.polyrhythm != nil },
            set: { isOn in
                settings.polyrhythm = isOn ? PolyrhythmConfig() : nil
            }
        )
    }

    private func polyPulsesBinding(currentValue: Int) -> Binding<Int> {
        Binding(
            get: { currentValue },
            set: { newValue in
                guard let poly = settings.polyrhythm else { return }
                settings.polyrhythm = PolyrhythmConfig(
                    pulses: newValue,
                    sound: poly.sound,
                    volume: poly.volume
                )
            }
        )
    }

    private func polySoundBinding(currentValue: ClickSound) -> Binding<ClickSound> {
        Binding(
            get: { currentValue },
            set: { newValue in
                guard let poly = settings.polyrhythm else { return }
                settings.polyrhythm = PolyrhythmConfig(
                    pulses: poly.pulses,
                    sound: newValue,
                    volume: poly.volume
                )
            }
        )
    }

    private func polyVolumeBinding(currentValue: Double) -> Binding<Double> {
        Binding(
            get: { currentValue },
            set: { newValue in
                guard let poly = settings.polyrhythm else { return }
                settings.polyrhythm = PolyrhythmConfig(
                    pulses: poly.pulses,
                    sound: poly.sound,
                    volume: newValue
                )
            }
        )
    }

    private var countInSection: some View {
        Section {
            Picker("Count-in", selection: $settings.countIn) {
                Text("Off").tag(CountIn.off)
                Text("1").tag(CountIn.oneMeasure)
                Text("2").tag(CountIn.twoMeasures)
                Text("4").tag(CountIn.fourMeasures)
            }
            .pickerStyle(.segmented)
            .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Count-in")
                .foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Measures of count-off before playback starts.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var masterVolumeSection: some View {
        Section {
            HStack(spacing: DS.Spacing.md) {
                Slider(value: $settings.masterVolume, in: 0...1)
                    .tint(DS.DSColor.accentTempo)
                Text("\(Int((settings.masterVolume * 100).rounded()))%")
                    .font(DS.Font.monoData)
                    .frame(width: 48, alignment: .trailing)
                    .foregroundStyle(DS.DSColor.textPrimary)
            }
            .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Master Volume")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var latencySection: some View {
        // Slider works in milliseconds; bind to a derived value so the
        // model keeps seconds (matching EngineSettings.latencyOffsetSeconds).
        let latencyMs = Binding(
            get: { settings.latencyOffsetSeconds * 1000 },
            set: { settings.latencyOffsetSeconds = $0 / 1000 }
        )
        let valueLabel: String = {
            let ms = Int(latencyMs.wrappedValue.rounded())
            return ms > 0 ? "+\(ms) ms" : "\(ms) ms"
        }()

        return Section {
            HStack(spacing: DS.Spacing.md) {
                Slider(value: latencyMs, in: -50...50, step: 1)
                    .tint(DS.DSColor.accentTempo)
                Text(valueLabel)
                    .font(DS.Font.monoData)
                    .frame(width: 64, alignment: .trailing)
                    .foregroundStyle(DS.DSColor.textPrimary)
            }
            .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Latency Calibration")
                .foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Negative values fire clicks earlier to compensate for Bluetooth headphone output delay.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var autoResumeSection: some View {
        Section {
            Toggle("Auto-resume after interruption", isOn: $settings.autoResumeAfterInterruption)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
            Toggle("Keep screen awake while playing", isOn: $settings.keepScreenAwakeDuringPlayback)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
            Toggle("Start on app launch", isOn: $settings.startOnLaunch)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
            dailyGoalRow
            weeklyGoalRow
            monthlyGoalRow
        } header: {
            Text("Playback Behavior").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Auto-resume restarts the metronome after a phone call or Siri ends. Keep-screen-awake prevents the display from sleeping mid-song. Goals are independent — set just the ones you want to track.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var voiceCountSection: some View {
        Section {
            Picker("Voice Count", selection: $settings.voiceCountMode) {
                ForEach(VoiceCountMode.allCases, id: \.self) { mode in
                    if mode.isImplemented {
                        Text(mode.displayName).tag(mode)
                    } else {
                        // Unimplemented modes still listed so users see
                        // what's coming; disabled state would need a custom
                        // picker — for now they just no-op as ".off".
                        Text("\(mode.displayName) (coming soon)").tag(mode)
                    }
                }
            }
            .pickerStyle(.menu)
            .tint(DS.DSColor.accentTempo)
            .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Voice Count").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Plays per-beat pitched tones instead of the click on main beats. Real spoken samples (\"one, two, three\") in 5 languages are planned — Phase 1 uses synthesized tones as a placeholder.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var midiSection: some View {
        Section {
            Toggle("Send MIDI Clock", isOn: $settings.midiClockEnabled)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
            Toggle("Listen for MIDI Clock", isOn: $settings.midiClockReceiveEnabled)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
            if settings.midiClockReceiveEnabled {
                midiSourcePicker
            }
        } header: {
            Text("MIDI Sync").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Send: publish a virtual MIDI source named \"meter-gnome\" that emits MIDI Clock (24 PPQ) + Start/Stop. Listen: follow incoming MIDI Clock from connected sources — DAW transport drives play/stop, DAW tempo drives BPM. Source: pick a specific master when more than one is on the bus (DAW + drum machine); All Sources merges every external source.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
        .task(id: settings.midiClockReceiveEnabled) {
            // Refresh when the sheet opens or when slave mode is just
            // turned on. CoreMIDI source enumeration is cheap; no need
            // to cache between sessions.
            if settings.midiClockReceiveEnabled {
                midiSources = await loadMIDISources()
            }
        }
    }

    /// Source picker row — shown only when "Listen for MIDI Clock" is
    /// on. The selection is `EngineSettings.midiReceiveSourceName?`;
    /// `nil` displays as "All Sources" and means "merge every external
    /// source" (legacy receiver behavior).
    private var midiSourcePicker: some View {
        Picker("Source", selection: $settings.midiReceiveSourceName) {
            Text("All Sources").tag(String?.none)
            ForEach(midiSources, id: \.self) { name in
                Text(name).tag(String?.some(name))
            }
            // If the persisted selection no longer matches any visible
            // source (e.g., DAW disconnected), still display it as a
            // disabled-looking row tagged with that name — picking it
            // again resumes filtering once the source comes back.
            if let selected = settings.midiReceiveSourceName,
               !midiSources.contains(selected) {
                Text("\(selected) (offline)").tag(String?.some(selected))
            }
        }
        .pickerStyle(.menu)
        .tint(DS.DSColor.accentTempo)
        .listRowBackground(DS.DSColor.bgElevated)
    }

    // MARK: - Daily practice goal (spec §11)

    private var dailyGoalRow: some View {
        goalRow(
            label: "Daily goal",
            value: $settings.dailyPracticeGoalMinutes,
            range: 0...240,
            step: 5
        )
    }

    /// Weekly goal — wider range than daily (an ambitious week of
    /// practice can run 5–10 hours), coarser step to keep the
    /// stepper press count reasonable.
    private var weeklyGoalRow: some View {
        goalRow(
            label: "Weekly goal",
            value: $settings.weeklyPracticeGoalMinutes,
            range: 0...1200,
            step: 15
        )
    }

    /// Monthly goal — even wider range, coarser still.
    private var monthlyGoalRow: some View {
        goalRow(
            label: "Monthly goal",
            value: $settings.monthlyPracticeGoalMinutes,
            range: 0...5000,
            step: 30
        )
    }

    private func goalRow(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(label).foregroundStyle(DS.DSColor.textPrimary)
                Spacer()
                Text(value.wrappedValue == 0 ? "Off" : "\(value.wrappedValue) min")
                    .font(DS.Font.monoData)
                    .foregroundStyle(DS.DSColor.textPrimary)
            }
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    // MARK: - Haptics (spec §9)

    private var hapticSection: some View {
        Section {
            Picker("Mode", selection: $settings.hapticMode) {
                ForEach(HapticMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .tint(DS.DSColor.accentTempo)
            .listRowBackground(DS.DSColor.bgElevated)

            if settings.hapticMode != .off {
                intensitySlider(label: "Soft", value: $settings.hapticIntensity.soft)
                intensitySlider(label: "Normal", value: $settings.hapticIntensity.normal)
                intensitySlider(label: "Loud", value: $settings.hapticIntensity.loud)
                intensitySlider(label: "Accent", value: $settings.hapticIntensity.accent)
            }
        } header: {
            Text("Haptics").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text(hapticFooter)
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var hapticFooter: String {
        if settings.hapticMode == .off {
            return "Vibrate on selected clicks. Useful for silent practice or wrist-feel reinforcement. Real device only — Simulator has no haptic engine."
        }
        return "Per-accent intensity for each beat level. Soft = subdivisions / mid-pattern. Accent = downbeats and explicitly-accented beats."
    }

    private func intensitySlider(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text(label).foregroundStyle(DS.DSColor.textPrimary)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(DS.Font.monoData)
                    .foregroundStyle(DS.DSColor.textPrimary)
            }
            Slider(value: value, in: 0...1)
                .tint(DS.DSColor.accentTempo)
                // Each haptic-intensity slider shares the "Haptics"
                // section header, so VoiceOver hears 4 unlabeled
                // sliders in a row without this override. Explicit
                // labels carry the accent level (Soft / Normal / …)
                // into the screen-reader stream.
                .accessibilityLabel("\(label) haptic intensity")
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    // MARK: - Random Mute (spec §6.4 speed-trainer practice mode)

    private var randomMuteEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.randomMutePercentage > 0 },
            // Toggling on snaps to the bottom of the active range (10%);
            // toggling off stores 0 so the slider hides cleanly.
            set: { isOn in
                settings.randomMutePercentage = isOn
                    ? EngineSettings.randomMuteRange.lowerBound
                    : 0
            }
        )
    }

    private var randomMuteSection: some View {
        Section {
            Toggle("Random Mute", isOn: randomMuteEnabledBinding)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)

            if settings.randomMutePercentage > 0 {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack {
                        Text("Probability").foregroundStyle(DS.DSColor.textPrimary)
                        Spacer()
                        Text("\(settings.randomMutePercentage)%")
                            .font(DS.Font.monoData)
                            .foregroundStyle(DS.DSColor.textPrimary)
                    }
                    let lo = Double(EngineSettings.randomMuteRange.lowerBound)
                    let hi = Double(EngineSettings.randomMuteRange.upperBound)
                    Slider(
                        value: Binding(
                            get: { Double(settings.randomMutePercentage) },
                            set: { settings.randomMutePercentage = Int($0.rounded()) }
                        ),
                        in: lo...hi,
                        step: 1
                    )
                    .tint(DS.DSColor.accentTempo)
                }
                .listRowBackground(DS.DSColor.bgElevated)
            }
        } header: {
            Text("Speed Trainer").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Randomly mutes the chosen percentage of beats during playback. Trains you to feel where the missing beat would be. Count-in beats are always audible. Range: 10–50%.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }
}

// MARK: - Subdivision config detail (spec §2.3)

/// Drill-in view that lists every subdivision level and lets the user
/// customize its accent + sound. Only levels actually represented in
/// `settings.subdivisionConfigs` differ from the legacy default —
/// everything else renders the placeholder ("Soft · Inherit") and
/// touching its sub-pickers materializes a real entry.
private struct SubdivisionConfigList: View {
    @Binding var settings: EngineSettings

    /// `.none` (quarters) has no sub clicks — skip it from the list.
    private static let editableLevels: [Subdivision] =
        Subdivision.allCases.filter { $0 != .none }

    var body: some View {
        Form {
            ForEach(Self.editableLevels, id: \.self) { level in
                Section {
                    accentPicker(for: level)
                    soundPicker(for: level)
                    if settings.subdivisionConfigs[level] != nil {
                        Button(role: .destructive) {
                            settings.subdivisionConfigs.removeValue(forKey: level)
                        } label: {
                            Text("Reset to Default")
                        }
                        .listRowBackground(DS.DSColor.bgElevated)
                    }
                } header: {
                    Text(level.displayName)
                        .foregroundStyle(DS.DSColor.textMuted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.DSColor.bgBase)
        .navigationTitle("Subdivisions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.DSColor.bgBase, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func accentPicker(for level: Subdivision) -> some View {
        Picker("Volume", selection: Binding(
            get: { settings.subdivisionConfigs[level]?.accent ?? .soft },
            set: { newAccent in
                var cfg = settings.subdivisionConfigs[level] ?? .legacy
                cfg.accent = newAccent
                // Don't materialize a row that equals the legacy default —
                // keeps the JSON map small and the "X custom" summary
                // honest.
                if cfg == .legacy {
                    settings.subdivisionConfigs.removeValue(forKey: level)
                } else {
                    settings.subdivisionConfigs[level] = cfg
                }
            }
        )) {
            Text("Mute").tag(AccentLevel.mute)
            Text("Soft").tag(AccentLevel.soft)
            Text("Normal").tag(AccentLevel.normal)
            Text("Loud").tag(AccentLevel.loud)
            Text("Accent").tag(AccentLevel.accent)
        }
        .pickerStyle(.menu)
        .tint(DS.DSColor.accentTempo)
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func soundPicker(for level: Subdivision) -> some View {
        Picker("Sound", selection: Binding<String?>(
            get: { settings.subdivisionConfigs[level]?.soundOverride },
            set: { newOverride in
                var cfg = settings.subdivisionConfigs[level] ?? .legacy
                cfg.soundOverride = newOverride
                if cfg == .legacy {
                    settings.subdivisionConfigs.removeValue(forKey: level)
                } else {
                    settings.subdivisionConfigs[level] = cfg
                }
            }
        )) {
            Text("Inherit").tag(String?.none)
            ForEach(ClickSound.allCases, id: \.self) { sound in
                Text(sound.displayName).tag(String?(sound.rawValue))
            }
        }
        .pickerStyle(.menu)
        .tint(DS.DSColor.accentTempo)
        .listRowBackground(DS.DSColor.bgElevated)
    }
}

#Preview {
    SettingsView(initial: EngineSettings()) { _ in }
}
