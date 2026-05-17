//
//  TimeSignaturePickerView.swift
//  meter-gnome
//
//  Sheet presented when the user taps the Stage view's time-signature
//  display, and when a multi-section row needs a custom time signature.
//  Two modes:
//
//  - Default: grid of 8 common presets (2/4 through 12/8) — the 95% case.
//  - Custom: numerator stepper (1–32, spec §2.1) + denominator picker
//    (1/2/4/8/16/32) for exotic meters like 11/8, 13/16, 9/4 etc.
//
//  The "Custom…" tile in the preset grid switches the body into custom
//  mode in-place; a Confirm button commits the selection. State is
//  initialized from `current` so toggling to custom preserves whatever
//  was already loaded.
//

import SwiftUI
import MetronomeCore

struct TimeSignaturePickerView: View {
    let current: TimeSignature
    let onSelect: (TimeSignature) -> Void

    @Environment(\.dismiss) private var dismiss

    /// When true, the body switches from the preset grid to the
    /// numerator+denominator detail editor. Initialized to true when
    /// `current` doesn't match any preset, so opening the picker on
    /// e.g. 11/8 lands in the editor.
    @State private var showCustom: Bool
    @State private var customNumerator: Int
    @State private var customDenominator: TimeSignature.Denominator

    private static let presets: [TimeSignature] = [
        .twoFour, .threeFour, .fourFour, .fiveFour,
        .sixEight, .sevenEight, .nineEight, .twelveEight,
    ]

    init(current: TimeSignature, onSelect: @escaping (TimeSignature) -> Void) {
        self.current = current
        self.onSelect = onSelect
        let matchesPreset = Self.presets.contains(current)
        self._showCustom = State(initialValue: !matchesPreset)
        self._customNumerator = State(initialValue: current.numerator)
        self._customDenominator = State(initialValue: current.denominator)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.DSColor.bgBase.ignoresSafeArea()
                if showCustom {
                    customEditor
                } else {
                    presetGrid
                }
            }
            .navigationTitle("Time Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.DSColor.textMuted)
                }
                if showCustom {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Set") {
                            if let ts = TimeSignature(
                                numerator: customNumerator,
                                denominator: customDenominator
                            ) {
                                onSelect(ts)
                                dismiss()
                            }
                        }
                        .foregroundStyle(DS.DSColor.accentTempo)
                    }
                }
            }
            .toolbarBackground(DS.DSColor.bgBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Preset grid

    private var presetGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: DS.Spacing.md)],
                spacing: DS.Spacing.md
            ) {
                ForEach(Self.presets, id: \.self) { ts in
                    presetButton(for: ts)
                }
                customTile
            }
            .padding(DS.Spacing.lg)
        }
    }

    /// Slot in the preset grid that switches to the custom editor.
    /// Visual rhythm matches the preset tiles so the affordance reads
    /// as "one more option, but more flexible."
    private var customTile: some View {
        Button {
            showCustom = true
        } label: {
            VStack(spacing: DS.Spacing.xxs) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                Text("Custom…")
                    .font(DS.Font.headline)
            }
            .foregroundStyle(DS.DSColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.DSColor.bgElevated)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Custom time signature")
    }

    // MARK: - Custom editor

    private var customEditor: some View {
        Form {
            Section {
                Stepper(value: $customNumerator, in: TimeSignature.minNumerator...TimeSignature.maxNumerator) {
                    HStack {
                        Text("Numerator").foregroundStyle(DS.DSColor.textPrimary)
                        Spacer()
                        Text("\(customNumerator)")
                            .font(DS.Font.monoData)
                            .foregroundStyle(DS.DSColor.accentTempo)
                    }
                }
                .listRowBackground(DS.DSColor.bgElevated)
                Picker("Denominator", selection: $customDenominator) {
                    ForEach(TimeSignature.Denominator.allCases, id: \.self) { d in
                        Text("\(d.rawValue)").tag(d)
                    }
                }
                .pickerStyle(.menu)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
            } header: {
                Text("Custom").foregroundStyle(DS.DSColor.textMuted)
            } footer: {
                Text("Numerator 1–32, denominator 1/2/4/8/16/32. Common odd meters: 11/8, 13/16, 9/4. Switch back to presets above for the standard set.")
                    .foregroundStyle(DS.DSColor.textMuted)
            }

            Section {
                Button {
                    showCustom = false
                } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                        Text("Back to Presets")
                    }
                }
                .foregroundStyle(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func presetButton(for ts: TimeSignature) -> some View {
        let isSelected = (ts == current)
        return Button {
            onSelect(ts)
            dismiss()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text("\(ts.numerator)")
                Text("/").foregroundStyle(DS.DSColor.textDim)
                Text("\(ts.denominator.rawValue)")
            }
            .font(DS.Font.display)
            .monospacedDigit()
            .foregroundStyle(isSelected ? DS.DSColor.accentTempo : DS.DSColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.DSColor.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .strokeBorder(DS.DSColor.accentTempo, lineWidth: isSelected ? 2 : 0)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ts.numerator) over \(ts.denominator.rawValue)")
    }
}

#Preview {
    TimeSignaturePickerView(current: .fourFour, onSelect: { _ in })
}
