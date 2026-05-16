//
//  AccentPatternEditView.swift
//  meter-gnome
//
//  Per-beat accent pattern editor (spec §3.1). Phase 1 ships per-beat
//  AccentLevel only — sound overrides + pitch shifts per beat are
//  modeled in BeatConfig but deferred to a later editor revision since
//  each adds another column of UI to every beat row.
//
//  Editor lifecycle:
//  - Seeded from the existing AccentPattern if the song has one; falls
//    back to AccentPattern.standard(for: timeSignature) otherwise.
//  - Save commits a new AccentPattern (with whatever name + beats the
//    user configured) via onSave(pattern).
//  - Reset commits `nil`, clearing the pattern (downbeat-only default).
//  - Cancel dismisses without committing.
//

import SwiftUI
import MetronomeCore

struct AccentPatternEditView: View {
    let timeSignature: TimeSignature
    let onSave: (AccentPattern?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    /// Per-beat configs. Each entry holds the accent + per-beat sound +
    /// per-beat pitch shift. The editor builds an AccentPattern from this
    /// array at save time.
    @State private var beats: [BeatConfig]

    init(
        timeSignature: TimeSignature,
        current: AccentPattern?,
        onSave: @escaping (AccentPattern?) -> Void
    ) {
        self.timeSignature = timeSignature
        self.onSave = onSave
        if let current {
            self._name = State(initialValue: current.name)
            self._beats = State(initialValue: current.beats)
        } else {
            self._name = State(initialValue: "Custom \(timeSignature.numerator)/\(timeSignature.denominator.rawValue)")
            // Seed from the standard pattern so beat 1 is .accent and
            // others are .normal — what users hear by default.
            self._beats = State(
                initialValue: AccentPattern.standard(for: timeSignature).beats
            )
        }
    }

    var body: some View {
        ZStack {
            DS.DSColor.bgBase.ignoresSafeArea()
            Form {
                nameSection
                beatsSection
                actionsSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Accent Pattern")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(DS.DSColor.textMuted)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    commit()
                }
                .foregroundStyle(DS.DSColor.accentTempo)
                .disabled(!isSaveable)
            }
        }
        .toolbarBackground(DS.DSColor.bgBase, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Pattern name", text: $name)
                .textInputAutocapitalization(.words)
                .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Name").foregroundStyle(DS.DSColor.textMuted)
        }
    }

    @ViewBuilder
    private var beatsSection: some View {
        // One Section per beat so each beat's three controls (accent +
        // sound + pitch) are visually grouped. Section header doubles as
        // the beat label.
        ForEach(0..<beats.count, id: \.self) { i in
            Section {
                accentRow(index: i)
                soundRow(index: i)
                pitchRow(index: i)
            } header: {
                Text("Beat \(i + 1)\(i == 0 ? " (Downbeat)" : "")")
                    .foregroundStyle(i == 0 ? DS.DSColor.accentTempo : DS.DSColor.textMuted)
            }
        }
    }

    private func accentRow(index i: Int) -> some View {
        HStack {
            Text("Accent").foregroundStyle(DS.DSColor.textPrimary)
            Spacer()
            Picker("Accent", selection: accentBinding(at: i)) {
                ForEach(AccentLevel.allCases, id: \.self) { level in
                    Text(AccentLevelLabel.short(level)).tag(level)
                }
            }
            .pickerStyle(.menu)
            .tint(beats[i].accent == .accent ? DS.DSColor.accentTempo : DS.DSColor.textPrimary)
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func soundRow(index i: Int) -> some View {
        HStack {
            Text("Sound").foregroundStyle(DS.DSColor.textPrimary)
            Spacer()
            Picker("Sound", selection: soundBinding(at: i)) {
                Text("Default").tag(String?.none)
                ForEach(ClickSound.allCases, id: \.self) { sound in
                    Text(sound.displayName).tag(String?.some(sound.rawValue))
                }
            }
            .pickerStyle(.menu)
            .tint(beats[i].soundOverride == nil ? DS.DSColor.textPrimary : DS.DSColor.accentTempo)
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func pitchRow(index i: Int) -> some View {
        HStack {
            Text("Pitch").foregroundStyle(DS.DSColor.textPrimary)
            Spacer()
            Picker("Pitch", selection: pitchBinding(at: i)) {
                Text("−1 oct").tag(PitchShift.octaveDown)
                Text("Unison").tag(PitchShift.unison)
                Text("+1 oct").tag(PitchShift.octaveUp)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    // MARK: - Bindings

    /// Bindings replace one field of BeatConfig at a time. BeatConfig's
    /// stored properties are `let`, so we build a fresh instance on every
    /// edit (struct value-copy semantics — cheap).
    private func accentBinding(at i: Int) -> Binding<AccentLevel> {
        Binding(
            get: { beats[i].accent },
            set: { newAccent in
                beats[i] = BeatConfig(
                    accent: newAccent,
                    soundOverride: beats[i].soundOverride,
                    pitchShift: beats[i].pitchShift
                )
            }
        )
    }

    private func soundBinding(at i: Int) -> Binding<String?> {
        Binding(
            get: { beats[i].soundOverride },
            set: { newSound in
                beats[i] = BeatConfig(
                    accent: beats[i].accent,
                    soundOverride: newSound,
                    pitchShift: beats[i].pitchShift
                )
            }
        )
    }

    private func pitchBinding(at i: Int) -> Binding<PitchShift> {
        Binding(
            get: { beats[i].pitchShift },
            set: { newPitch in
                beats[i] = BeatConfig(
                    accent: beats[i].accent,
                    soundOverride: beats[i].soundOverride,
                    pitchShift: newPitch
                )
            }
        )
    }

    private var actionsSection: some View {
        Section {
            Button(role: .destructive) {
                // Reset → clear the pattern. Song falls back to the
                // engine's default downbeat-only rule.
                onSave(nil)
                dismiss()
            } label: {
                Text("Reset to Default (Downbeat Only)")
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(DS.DSColor.bgElevated)
        }
    }

    // MARK: - Commit

    private var isSaveable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pattern = AccentPattern(
            name: trimmed,
            timeSignature: timeSignature,
            beats: beats
        ) {
            onSave(pattern)
            dismiss()
        }
    }
}

/// Centralized labels for AccentLevel so editor + future displays stay
/// consistent.
enum AccentLevelLabel {
    static func short(_ level: AccentLevel) -> String {
        switch level {
        case .mute:   "Mute"
        case .soft:   "Soft"
        case .normal: "Normal"
        case .loud:   "Loud"
        case .accent: "Accent"
        }
    }
}

#Preview {
    NavigationStack {
        AccentPatternEditView(
            timeSignature: .fourFour,
            current: nil,
            onSave: { _ in }
        )
    }
}
