//
//  AccentPatternLibraryView.swift
//  meter-gnome
//
//  Browse / rename / edit / delete the named accent-pattern preset
//  library (spec §3.2) standalone — without going through a song. Sits
//  as a fourth tab in LibraryView alongside Songs / Setlists / Stats.
//
//  Edit + create flows reuse AccentPatternEditView via sheet so the
//  per-beat picker UI stays in one place. Save routes through
//  viewModel.updateAccentPatternPreset (preserving UUID) for edits and
//  viewModel.saveAccentPatternPreset for new patterns.
//

import SwiftUI
import MetronomeCore

struct AccentPatternLibraryView: View {
    @Bindable var viewModel: MetronomeViewModel

    /// Non-nil while the edit sheet is showing for an existing preset.
    /// On save, the preset is updated in place (UUID preserved).
    @State private var editingPreset: AccentPatternPreset?
    /// Non-nil while the new-pattern sheet is showing. The selected
    /// time signature drives the editor's initial blank state.
    @State private var creatingForTimeSig: TimeSignature?
    @State private var showCreateMenu: Bool = false

    var body: some View {
        Group {
            if viewModel.accentPatternPresets.isEmpty {
                emptyState
            } else {
                presetList
            }
        }
        .onAppear { viewModel.refreshAccentPatternPresets() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreateMenu = true } label: {
                    Image(systemName: "plus")
                }
                .foregroundStyle(DS.DSColor.accentTempo)
                .accessibilityLabel("New pattern")
            }
        }
        .confirmationDialog(
            "Time signature for new pattern",
            isPresented: $showCreateMenu,
            titleVisibility: .visible
        ) {
            ForEach(Self.commonTimeSigs, id: \.self) { ts in
                Button("\(ts.numerator)/\(ts.denominator.rawValue)") {
                    creatingForTimeSig = ts
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $editingPreset) { preset in
            NavigationStack {
                AccentPatternEditView(
                    timeSignature: preset.pattern.timeSignature,
                    current: preset.pattern,
                    viewModel: viewModel
                ) { newPattern in
                    if let newPattern {
                        var updated = preset
                        updated.name = newPattern.name
                        updated.pattern = newPattern
                        viewModel.updateAccentPatternPreset(updated)
                    }
                    // onSave(nil) from the editor's "Reset" path means
                    // "clear back to defaults." For a preset, that's
                    // equivalent to no-op — we don't want to delete the
                    // preset just because the user reset its beats.
                    editingPreset = nil
                }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(item: $creatingForTimeSig) { ts in
            NavigationStack {
                AccentPatternEditView(
                    timeSignature: ts,
                    current: nil,
                    viewModel: viewModel
                ) { newPattern in
                    if let newPattern {
                        viewModel.saveAccentPatternPreset(
                            name: newPattern.name,
                            pattern: newPattern
                        )
                    }
                    creatingForTimeSig = nil
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Sections

    private var presetList: some View {
        List {
            ForEach(groupedPresets, id: \.timeSig) { group in
                Section {
                    ForEach(group.presets) { preset in
                        Button {
                            editingPreset = preset
                        } label: {
                            presetRow(preset)
                        }
                        .listRowBackground(DS.DSColor.bgElevated)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteAccentPatternPreset(id: preset.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("\(group.timeSig.numerator)/\(group.timeSig.denominator.rawValue)")
                        .font(DS.Font.label)
                        .tracking(2)
                        .foregroundStyle(DS.DSColor.textMuted)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "waveform.path")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DS.DSColor.textDim)
            Text("No saved patterns yet")
                .font(DS.Font.headline)
                .foregroundStyle(DS.DSColor.textPrimary)
            Text("Tap + to create a pattern, or use Add Starter Presets from any song's accent editor.")
                .font(DS.Font.body)
                .foregroundStyle(DS.DSColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xxl)
        }
    }

    // MARK: - Row

    private func presetRow(_ preset: AccentPatternPreset) -> some View {
        HStack(spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(preset.name)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.DSColor.textPrimary)
                accentDots(for: preset.pattern.beats)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(DS.DSColor.textDim)
        }
        .padding(.vertical, DS.Spacing.xs)
        .contentShape(Rectangle())
    }

    /// Horizontal row of dots sized + opacity'd to convey accent level
    /// at a glance. Mute is hollow, soft is small + dim, normal is
    /// medium, loud is larger, accent is the brightest + biggest. Same
    /// visual language the editor uses on its accent dots.
    private func accentDots(for beats: [BeatConfig]) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(Array(beats.enumerated()), id: \.offset) { _, beat in
                accentDot(for: beat.accent)
            }
        }
    }

    @ViewBuilder
    private func accentDot(for level: AccentLevel) -> some View {
        let (size, opacity, fill): (CGFloat, Double, Color) = {
            switch level {
            case .mute:   return (5, 0.3, DS.DSColor.textDim)
            case .soft:   return (5, 0.6, DS.DSColor.textMuted)
            case .normal: return (6, 0.9, DS.DSColor.textPrimary)
            case .loud:   return (7, 1.0, DS.DSColor.accentTempo)
            case .accent: return (8, 1.0, DS.DSColor.accentTempo)
            }
        }()
        Circle()
            .fill(fill)
            .opacity(opacity)
            .frame(width: size, height: size)
    }

    // MARK: - Grouping helpers

    private struct PresetGroup: Hashable {
        let timeSig: TimeSignature
        let presets: [AccentPatternPreset]
    }

    /// Presets grouped by time signature, sorted (numerator, denominator)
    /// ascending so 3/4 sits above 4/4 sits above 7/8 etc. Within each
    /// group, presets are sorted by display name.
    private var groupedPresets: [PresetGroup] {
        let byTS = Dictionary(grouping: viewModel.accentPatternPresets) {
            $0.pattern.timeSignature
        }
        return byTS
            .map { PresetGroup(timeSig: $0.key, presets: $0.value.sorted { $0.name < $1.name }) }
            .sorted { lhs, rhs in
                if lhs.timeSig.numerator != rhs.timeSig.numerator {
                    return lhs.timeSig.numerator < rhs.timeSig.numerator
                }
                return lhs.timeSig.denominator.rawValue < rhs.timeSig.denominator.rawValue
            }
    }

    private static let commonTimeSigs: [TimeSignature] = [
        .fourFour,
        TimeSignature(numerator: 3, denominator: .quarter)!,
        TimeSignature(numerator: 6, denominator: .eighth)!,
        TimeSignature(numerator: 5, denominator: .quarter)!,
        TimeSignature(numerator: 7, denominator: .eighth)!,
    ]
}

// Identifiable conformance so .sheet(item:) can drive presentation
// from the optional state. TimeSignature is Hashable but not Id, so
// we provide an extension scoped to this file's needs.
extension TimeSignature: @retroactive Identifiable {
    public var id: Int { numerator * 100 + denominator.rawValue }
}
