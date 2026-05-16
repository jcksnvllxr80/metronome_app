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
    @State private var beats: [AccentLevel]

    init(
        timeSignature: TimeSignature,
        current: AccentPattern?,
        onSave: @escaping (AccentPattern?) -> Void
    ) {
        self.timeSignature = timeSignature
        self.onSave = onSave
        if let current {
            self._name = State(initialValue: current.name)
            self._beats = State(initialValue: current.beats.map(\.accent))
        } else {
            self._name = State(initialValue: "Custom \(timeSignature.numerator)/\(timeSignature.denominator.rawValue)")
            // Seed from the standard pattern so beat 1 is .accent and
            // others are .normal — what users hear by default.
            self._beats = State(
                initialValue: AccentPattern.standard(for: timeSignature).beats.map(\.accent)
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

    private var beatsSection: some View {
        Section {
            ForEach(0..<beats.count, id: \.self) { i in
                beatRow(index: i)
            }
        } header: {
            Text("Per-Beat Accent (\(timeSignature.numerator)/\(timeSignature.denominator.rawValue))")
                .foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Per-beat sound and pitch overrides coming soon.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private func beatRow(index i: Int) -> some View {
        HStack {
            // Beat label — bold on the downbeat to anchor the row visually.
            Text("Beat \(i + 1)")
                .font(i == 0 ? DS.Font.headline : DS.Font.body)
                .foregroundStyle(DS.DSColor.textPrimary)
            Spacer()
            Picker("Accent", selection: $beats[i]) {
                ForEach(AccentLevel.allCases, id: \.self) { level in
                    Text(AccentLevelLabel.short(level)).tag(level)
                }
            }
            .pickerStyle(.menu)
            .tint(beats[i] == .accent ? DS.DSColor.accentTempo : DS.DSColor.textPrimary)
        }
        .listRowBackground(DS.DSColor.bgElevated)
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
        let configs = beats.map { BeatConfig(accent: $0) }
        if let pattern = AccentPattern(
            name: trimmed,
            timeSignature: timeSignature,
            beats: configs
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
