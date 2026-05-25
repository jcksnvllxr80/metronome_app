//
//  TempoMarkingPickerView.swift
//  meter-gnome
//
//  Italian tempo preset picker (spec §6.2). Presented as a sheet from
//  tapping the BPM hero on Stage. Each marking is a chip showing the
//  name + canonical BPM range; tapping a chip sets the engine to the
//  range's midpoint and dismisses.
//
//  The currently-active marking (the one whose range contains the
//  current BPM) is highlighted in vermillion so the user can see what
//  the current tempo is "called" without doing the conversion in
//  their head.
//

import SwiftUI
import MetronomeCore

struct TempoMarkingPickerView: View {
    let currentBPM: BPM
    let onSelect: (BPM) -> Void

    @Environment(\.dismiss) private var dismiss

    private var activeMarking: TempoMarking? {
        TempoMarking.primaryMarking(for: currentBPM)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.DSColor.bgBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(TempoMarking.all) { marking in
                            markingRow(marking)
                        }
                    }
                    .padding(DS.Spacing.lg)
                }
            }
            .navigationTitle("Tempo Preset")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.DSColor.accentTempo)
                }
            }
            .compatBarBackground(DS.DSColor.bgBase)
        }
        .preferredColorScheme(.dark)
    }

    private func markingRow(_ marking: TempoMarking) -> some View {
        let isActive = (marking.id == activeMarking?.id)
        return Button {
            onSelect(marking.defaultBPM)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(marking.name)
                        .font(DS.Font.headline)
                        .foregroundStyle(isActive ? DS.DSColor.accentTempo : DS.DSColor.textPrimary)
                    Text(rangeLabel(for: marking))
                        .font(DS.Font.label)
                        .foregroundStyle(DS.DSColor.textMuted)
                }
                Spacer()
                Text("\(marking.defaultBPM.displayInt)")
                    .font(DS.Font.monoData)
                    .foregroundStyle(isActive ? DS.DSColor.accentTempo : DS.DSColor.textPrimary)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.DSColor.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(isActive ? DS.DSColor.accentTempo : Color.clear, lineWidth: 1.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(marking.name), \(rangeLabel(for: marking)), \(isActive ? "current" : "tap to set")")
    }

    /// Format the range as "120 – 168" — for Prestissimo (open upper
    /// bound at BPM.maximum + 1), show "200+" instead.
    private func rangeLabel(for marking: TempoMarking) -> String {
        let lower = Int(marking.bpmRange.lowerBound)
        let upper = Int(marking.bpmRange.upperBound)
        if upper > Int(BPM.maximum) {
            return "\(lower)+ BPM"
        }
        // Subtract 1 from upper since the range is half-open [lower, upper).
        return "\(lower) – \(upper - 1) BPM"
    }
}

#Preview {
    TempoMarkingPickerView(currentBPM: BPM(140)) { _ in }
}
