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

    @Environment(\.dismiss) private var dismiss
    @State private var settings: EngineSettings

    init(initial: EngineSettings, onChange: @escaping (EngineSettings) -> Void) {
        self.initial = initial
        self.onChange = onChange
        self._settings = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                soundSection
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
        } header: {
            Text("Sound")
                .foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Default click sound. Individual songs can override this in their detail view.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
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
        } footer: {
            Text("When enabled, the metronome resumes automatically after a phone call or Siri interruption ends. Off by default — most musicians prefer to restart manually.")
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
        } header: {
            Text("MIDI Sync").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Send: publish a virtual MIDI source named \"meter-gnome\" that emits MIDI Clock (24 PPQ) + Start/Stop. Listen: follow incoming MIDI Clock from connected sources — DAW transport drives play/stop, DAW tempo drives BPM.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
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

#Preview {
    SettingsView(initial: EngineSettings()) { _ in }
}
