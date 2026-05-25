//
//  SubdivisionPickerView.swift
//  meter-gnome
//
//  Sheet for picking the per-beat subdivision (spec §2.3). Lists all 9
//  cases with descriptive names and the ÷N annotation that matches the
//  Stage view's compact label. The currently active subdivision is shown
//  with a vermillion border.
//

import SwiftUI
import MetronomeCore

struct SubdivisionPickerView: View {
    let current: Subdivision
    let onSelect: (Subdivision) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                DS.DSColor.bgBase.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: DS.Spacing.sm) {
                        ForEach(Subdivision.allCases, id: \.self) { sub in
                            row(for: sub)
                        }
                    }
                    .padding(DS.Spacing.lg)
                }
            }
            .navigationTitle("Subdivision")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.DSColor.textMuted)
                }
            }
            .compatBarBackground(DS.DSColor.bgBase)
        }
        .preferredColorScheme(.dark)
    }

    private func row(for sub: Subdivision) -> some View {
        let isSelected = (sub == current)
        return Button {
            onSelect(sub)
            dismiss()
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Text(SubdivisionLabel.compact(sub))
                    .font(DS.Font.display)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? DS.DSColor.accentTempo : DS.DSColor.textPrimary)
                    .frame(minWidth: 48, alignment: .leading)
                Text(SubdivisionLabel.descriptive(sub))
                    .font(DS.Font.body)
                    .foregroundStyle(isSelected ? DS.DSColor.textPrimary : DS.DSColor.textMuted)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.DSColor.accentTempo)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
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
        .accessibilityLabel("\(SubdivisionLabel.descriptive(sub))\(isSelected ? ", currently selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Centralized label formatting so Stage and the picker stay consistent.
enum SubdivisionLabel {
    /// Stage-style compact label: "÷1" through "÷9".
    static func compact(_ sub: Subdivision) -> String {
        "÷\(sub.partsPerBeat)"
    }

    /// Picker-style human-readable label.
    static func descriptive(_ sub: Subdivision) -> String {
        switch sub {
        case .none:       "Off (quarter notes only)"
        case .eighth:     "Eighth notes"
        case .triplet:    "Triplets"
        case .sixteenth:  "Sixteenth notes"
        case .quintuplet: "Quintuplets"
        case .sextuplet:  "Sextuplets"
        case .septuplet:  "Septuplets"
        case .octuplet:   "Octuplets"
        case .nonuplet:   "Nonuplets"
        }
    }
}

#Preview {
    SubdivisionPickerView(current: .triplet, onSelect: { _ in })
}
