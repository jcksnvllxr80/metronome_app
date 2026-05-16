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
                countInSection
                masterVolumeSection
                latencySection
                autoResumeSection
                midiSection
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
}

#Preview {
    SettingsView(initial: EngineSettings()) { _ in }
}
