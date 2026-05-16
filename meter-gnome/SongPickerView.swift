//
//  SongPickerView.swift
//  meter-gnome
//
//  Multi-select picker over the user's library songs. Presented from
//  SetlistDetailView when the user taps + to add songs. Selection is
//  by Set<UUID>; tapping a row toggles its check mark. Confirm passes
//  the selected songs back to the parent in the original library order.
//
//  Doesn't dedupe against songs already in the setlist — adding the
//  same song twice is intentional (a tune can recur in a set). Most
//  users won't, but the picker doesn't get in the way if they do.
//

import SwiftUI
import MetronomeCore

struct SongPickerView: View {
    let availableSongs: [Song]
    let onConfirm: ([Song]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ZStack {
                DS.DSColor.bgBase.ignoresSafeArea()
                if availableSongs.isEmpty {
                    emptyState
                } else {
                    songList
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.DSColor.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let picked = availableSongs.filter { selectedIDs.contains($0.id) }
                        onConfirm(picked)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                    .foregroundStyle(selectedIDs.isEmpty ? DS.DSColor.textDim : DS.DSColor.accentTempo)
                }
            }
            .toolbarBackground(DS.DSColor.bgBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "music.note")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DS.DSColor.textDim)
            Text("No songs in your library yet")
                .font(DS.Font.headline)
                .foregroundStyle(DS.DSColor.textPrimary)
            Text("Save a song from the Songs tab first.")
                .font(DS.Font.body)
                .foregroundStyle(DS.DSColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xxl)
        }
    }

    private var songList: some View {
        List {
            ForEach(availableSongs) { song in
                Button {
                    if selectedIDs.contains(song.id) {
                        selectedIDs.remove(song.id)
                    } else {
                        selectedIDs.insert(song.id)
                    }
                } label: {
                    row(song)
                }
                .buttonStyle(.plain)
                .listRowBackground(DS.DSColor.bgElevated)
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.DSColor.bgBase)
    }

    private func row(_ song: Song) -> some View {
        let isSelected = selectedIDs.contains(song.id)
        return HStack(spacing: DS.Spacing.md) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(isSelected ? DS.DSColor.accentTempo : DS.DSColor.textDim)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(song.title)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.DSColor.textPrimary)
                Text("\(song.bpm.displayInt) BPM · \(song.timeSignature.numerator)/\(song.timeSignature.denominator.rawValue)")
                    .font(DS.Font.monoData)
                    .foregroundStyle(DS.DSColor.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, DS.Spacing.xs)
        .contentShape(Rectangle())
    }
}

#Preview {
    SongPickerView(availableSongs: [], onConfirm: { _ in })
}
