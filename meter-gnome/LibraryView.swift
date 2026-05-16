//
//  LibraryView.swift
//  meter-gnome
//
//  Songs-only library sheet. Setlists are deferred — building a setlist
//  needs a song-picker UI that's its own surface. Phase 1 ships the
//  single-song-load path; setlists land alongside song-picking + ordering.
//
//  Flows:
//  - Tap "+" → alert with TextField → save current engine state as Song
//  - Tap a row → engine.apply(song), sheet dismisses
//  - Swipe row left → Delete
//  - Empty state shown when no songs are saved
//

import SwiftUI
import MetronomeCore

struct LibraryView: View {
    @Bindable var viewModel: MetronomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSaveAlert = false
    @State private var newSongTitle = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DS.DSColor.bgBase.ignoresSafeArea()
                if viewModel.librarySongs.isEmpty {
                    emptyState
                } else {
                    songList
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.DSColor.accentTempo)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newSongTitle = defaultSongTitle()
                        showSaveAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundStyle(DS.DSColor.accentTempo)
                    .accessibilityLabel("Save current as song")
                }
            }
            .toolbarBackground(DS.DSColor.bgBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Save as Song", isPresented: $showSaveAlert) {
                TextField("Song name", text: $newSongTitle)
                    .textInputAutocapitalization(.words)
                Button("Save") {
                    if viewModel.saveCurrentAsSong(title: newSongTitle) {
                        newSongTitle = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newSongTitle = ""
                }
            } message: {
                Text("Saves the current BPM, time signature, and subdivision.")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.refreshLibrary()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DS.DSColor.textDim)
            Text("No saved songs yet")
                .font(DS.Font.headline)
                .foregroundStyle(DS.DSColor.textPrimary)
            Text("Tap + to save the current tempo as a song.")
                .font(DS.Font.body)
                .foregroundStyle(DS.DSColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xxl)
        }
    }

    // MARK: - Song list

    private var songList: some View {
        List {
            ForEach(viewModel.librarySongs) { song in
                Button {
                    viewModel.loadSong(song)
                    dismiss()
                } label: {
                    songRow(song)
                }
                .buttonStyle(.plain)
                .listRowBackground(DS.DSColor.bgElevated)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteSong(id: song.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.DSColor.bgBase)
    }

    private func songRow(_ song: Song) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(song.title)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.DSColor.textPrimary)
                Text(metaLine(for: song))
                    .font(DS.Font.monoData)
                    .foregroundStyle(DS.DSColor.textMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.DSColor.textDim)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func metaLine(for song: Song) -> String {
        var parts: [String] = []
        parts.append("\(song.bpm.displayInt) BPM")
        parts.append("\(song.timeSignature.numerator)/\(song.timeSignature.denominator.rawValue)")
        if song.subdivision != .none {
            parts.append(song.subdivision.rawValue)
        }
        return parts.joined(separator: " · ")
    }

    private func defaultSongTitle() -> String {
        // Suggest "120 BPM, 4/4" so the user doesn't always face a blank field.
        let bpm = viewModel.bpm.displayInt
        let ts = viewModel.timeSignature
        return "\(bpm) BPM, \(ts.numerator)/\(ts.denominator.rawValue)"
    }
}

#Preview {
    LibraryView(viewModel: MetronomeViewModel())
}
