//
//  LibraryView.swift
//  meter-gnome
//
//  Two-tab library: Songs and Setlists. Songs tab supports saving the
//  engine's current state and loading any saved song. Setlists tab
//  supports CRUD on setlists; tap one to push into SetlistDetailView
//  for managing its songs and advance mode. Setlist playback (auto-
//  advance walkthrough) is a separate body of work — this view only
//  manages the data.
//

import SwiftUI
import MetronomeCore

private enum LibraryTab: String, Hashable {
    case songs, setlists, patterns, stats
}

struct LibraryView: View {
    @Bindable var viewModel: MetronomeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tab: LibraryTab = .songs
    @State private var showSaveSongAlert = false
    @State private var showNewSetlistAlert = false
    @State private var newSongTitle = ""
    @State private var newSetlistName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DS.DSColor.bgBase.ignoresSafeArea()
                switch tab {
                case .songs:    songsTab
                case .setlists: setlistsTab
                case .patterns: AccentPatternLibraryView(viewModel: viewModel)
                case .stats:    StatsView(viewModel: viewModel)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.DSColor.accentTempo)
                }
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $tab) {
                        Text("Songs").tag(LibraryTab.songs)
                        Text("Setlists").tag(LibraryTab.setlists)
                        Text("Patterns").tag(LibraryTab.patterns)
                        Text("Stats").tag(LibraryTab.stats)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
                if tab == .songs || tab == .setlists {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            switch tab {
                            case .songs:
                                newSongTitle = defaultSongTitle()
                                showSaveSongAlert = true
                            case .setlists:
                                newSetlistName = defaultSetlistName()
                                showNewSetlistAlert = true
                            case .patterns, .stats:
                                // Patterns has its own toolbar +
                                // button supplied by the inner view;
                                // Stats has no add action.
                                break
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .foregroundStyle(DS.DSColor.accentTempo)
                        .accessibilityLabel(tab == .songs ? "Save current as song" : "New setlist")
                    }
                }
            }
            .toolbarBackground(DS.DSColor.bgBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Save as Song", isPresented: $showSaveSongAlert) {
                TextField("Song name", text: $newSongTitle)
                    .textInputAutocapitalization(.words)
                Button("Save") {
                    if viewModel.saveCurrentAsSong(title: newSongTitle) {
                        newSongTitle = ""
                    }
                }
                Button("Cancel", role: .cancel) { newSongTitle = "" }
            } message: {
                Text("Saves the current BPM, time signature, and subdivision.")
            }
            .alert("New Setlist", isPresented: $showNewSetlistAlert) {
                TextField("Setlist name", text: $newSetlistName)
                    .textInputAutocapitalization(.words)
                Button("Create") {
                    _ = viewModel.createSetlist(name: newSetlistName)
                    newSetlistName = ""
                }
                Button("Cancel", role: .cancel) { newSetlistName = "" }
            } message: {
                Text("Setlists are ordered collections of saved songs.")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.refreshLibrary()
        }
    }

    // MARK: - Songs tab

    @ViewBuilder
    private var songsTab: some View {
        if viewModel.librarySongs.isEmpty {
            emptyState(
                icon: "music.note.list",
                title: "No saved songs yet",
                hint: "Tap + to save the current tempo as a song."
            )
        } else {
            List {
                ForEach(viewModel.librarySongs) { song in
                    NavigationLink {
                        SongDetailView(
                            song: song,
                            viewModel: viewModel,
                            onSave: { updated in viewModel.saveSong(updated) },
                            onDelete: { id in viewModel.deleteSong(id: id) },
                            onLoad: { toLoad in
                                viewModel.loadSong(toLoad)
                                dismiss()
                            }
                        )
                    } label: {
                        songRow(song)
                    }
                    .listRowBackground(DS.DSColor.bgElevated)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteSong(id: song.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            viewModel.duplicateSong(song)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(DS.DSColor.accentTempo)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Setlists tab

    @ViewBuilder
    private var setlistsTab: some View {
        if viewModel.librarySetlists.isEmpty {
            emptyState(
                icon: "list.bullet.rectangle",
                title: "No setlists yet",
                hint: "Tap + to create one. Setlists hold an ordered collection of your saved songs."
            )
        } else {
            List {
                ForEach(viewModel.librarySetlists) { setlist in
                    NavigationLink {
                        SetlistDetailView(
                            setlist: setlist,
                            availableSongs: viewModel.librarySongs,
                            onSave: { updated in
                                viewModel.saveSetlist(updated)
                            },
                            onSelectSong: { song in
                                viewModel.loadSong(song)
                                dismiss()
                            },
                            onPlay: { setlistToPlay in
                                viewModel.playSetlist(setlistToPlay)
                                dismiss()
                            }
                        )
                    } label: {
                        setlistRow(setlist)
                    }
                    .listRowBackground(DS.DSColor.bgElevated)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteSetlist(id: setlist.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Rows

    private func songRow(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(song.title)
                .font(DS.Font.headline)
                .foregroundStyle(DS.DSColor.textPrimary)
            Text(songMetaLine(song))
                .font(DS.Font.monoData)
                .foregroundStyle(DS.DSColor.textMuted)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func setlistRow(_ setlist: Setlist) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(setlist.name)
                .font(DS.Font.headline)
                .foregroundStyle(DS.DSColor.textPrimary)
            Text("\(setlist.count) \(setlist.count == 1 ? "song" : "songs")")
                .font(DS.Font.monoData)
                .foregroundStyle(DS.DSColor.textMuted)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - Empty state

    private func emptyState(icon: String, title: String, hint: String) -> some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DS.DSColor.textDim)
            Text(title)
                .font(DS.Font.headline)
                .foregroundStyle(DS.DSColor.textPrimary)
            Text(hint)
                .font(DS.Font.body)
                .foregroundStyle(DS.DSColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xxl)
        }
    }

    // MARK: - Helpers

    private func songMetaLine(_ song: Song) -> String {
        var parts: [String] = []
        parts.append("\(song.bpm.displayInt) BPM")
        parts.append("\(song.timeSignature.numerator)/\(song.timeSignature.denominator.rawValue)")
        if song.subdivision != .none {
            parts.append(song.subdivision.rawValue)
        }
        switch song.duration {
        case .measures(let n): parts.append("\(n)m")
        case .seconds(let s): parts.append("\(Int(s.rounded()))s")
        case .none: break
        }
        return parts.joined(separator: " · ")
    }

    private func defaultSongTitle() -> String {
        let bpm = viewModel.bpm.displayInt
        let ts = viewModel.timeSignature
        return "\(bpm) BPM, \(ts.numerator)/\(ts.denominator.rawValue)"
    }

    private func defaultSetlistName() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }
}

#Preview {
    LibraryView(viewModel: MetronomeViewModel())
}
