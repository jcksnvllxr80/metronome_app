//
//  TimeSignaturePickerView.swift
//  meter-gnome
//
//  Sheet presented when the user taps the Stage view's time-signature
//  display. First pass: 8 common presets (2/4 through 12/8). Custom
//  numerators 1–32 and full denominator selection are a follow-up — the
//  spec supports them (§2.1), but they're a more involved picker UI and
//  the presets cover the 95% case.
//

import SwiftUI
import MetronomeCore

struct TimeSignaturePickerView: View {
    let current: TimeSignature
    let onSelect: (TimeSignature) -> Void

    @Environment(\.dismiss) private var dismiss

    private static let presets: [TimeSignature] = [
        .twoFour, .threeFour, .fourFour, .fiveFour,
        .sixEight, .sevenEight, .nineEight, .twelveEight,
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DS.DSColor.bgBase.ignoresSafeArea()
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110), spacing: DS.Spacing.md)],
                        spacing: DS.Spacing.md
                    ) {
                        ForEach(Self.presets, id: \.self) { ts in
                            presetButton(for: ts)
                        }
                    }
                    .padding(DS.Spacing.lg)
                }
            }
            .navigationTitle("Time Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.DSColor.textMuted)
                }
            }
            .toolbarBackground(DS.DSColor.bgBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
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
