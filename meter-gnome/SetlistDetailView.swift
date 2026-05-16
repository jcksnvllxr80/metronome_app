//
//  SetlistDetailView.swift
//  meter-gnome
//
//  Editing surface for a single setlist. Lets the user:
//  - Pick auto-advance mode (Pause / Countdown / Immediate)
//  - Reorder songs via drag (List is always in edit mode)
//  - Swipe a song row to remove it from this setlist (doesn't delete
//    the library song)
//  - Add songs from the library via a multi-select picker sheet
//  - Tap a song row to load it into the engine and dismiss
//
//  Every mutation immediately persists via `onSave`. Cheaper than a
//  buffered-then-commit flow at our data size and saves the user from
//  losing edits if they navigate away mid-change.
//

import SwiftUI
import MetronomeCore

struct SetlistDetailView: View {
    @State var setlist: Setlist
    let availableSongs: [Song]
    let onSave: (Setlist) -> Void
    let onSelectSong: (Song) -> Void
    let onPlay: (Setlist) -> Void

    @State private var showSongPicker = false
    /// Remembers the user's last-chosen countdown measure count so toggling
    /// the advance mode kind (pause → countdown again) preserves it instead
    /// of resetting to 1. Initialized from setlist.advanceMode on appear.
    @State private var lastCountdownMeasures: Int = 1

    var body: some View {
        ZStack {
            DS.DSColor.bgBase.ignoresSafeArea()
            List {
                advanceModeSection
                songsSection
            }
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle(setlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSongPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .foregroundStyle(DS.DSColor.accentTempo)
                .accessibilityLabel("Add songs to setlist")
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    onPlay(setlist)
                } label: {
                    Label("Play Setlist", systemImage: "play.fill")
                        .font(DS.Font.headline)
                }
                .disabled(setlist.songs.isEmpty)
                .foregroundStyle(setlist.songs.isEmpty ? DS.DSColor.textDim : DS.DSColor.accentTempo)
            }
        }
        .toolbarBackground(DS.DSColor.bgBase, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showSongPicker) {
            SongPickerView(availableSongs: availableSongs) { picked in
                setlist.songs.append(contentsOf: picked)
                onSave(setlist)
            }
        }
        .onAppear {
            // Seed the remembered measure count from the saved setlist
            // so re-entering this view doesn't reset to 1.
            if case .countdown(let m) = setlist.advanceMode {
                lastCountdownMeasures = m
            }
        }
    }

    // MARK: - Advance mode

    private var advanceModeSection: some View {
        Section {
            Picker("Auto-advance", selection: advanceModeKindBinding) {
                Text("Pause").tag(AdvanceModeKind.pause)
                Text("Countdown").tag(AdvanceModeKind.countdown)
                Text("Immediate").tag(AdvanceModeKind.immediate)
            }
            .pickerStyle(.segmented)
            .listRowBackground(DS.DSColor.bgElevated)

            // Sub-picker for countdown measures — only when countdown is
            // the active kind. Constrained to 1/2/4 because SetlistPlayer
            // converts to CountIn (.oneMeasure / .twoMeasures /
            // .fourMeasures); anything else falls through to .off.
            if case .countdown = setlist.advanceMode {
                HStack {
                    Text("Measures")
                        .foregroundStyle(DS.DSColor.textPrimary)
                    Spacer()
                    Picker("Measures", selection: countdownMeasuresBinding) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("4").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                }
                .listRowBackground(DS.DSColor.bgElevated)
            }
        } header: {
            Text("Auto-advance")
                .foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text(advanceModeFooter)
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var countdownMeasuresBinding: Binding<Int> {
        Binding(
            get: {
                if case .countdown(let m) = setlist.advanceMode { return m }
                return lastCountdownMeasures
            },
            set: { newM in
                lastCountdownMeasures = newM
                setlist.advanceMode = .countdown(measures: newM)
                onSave(setlist)
            }
        )
    }

    /// Translates between the rich `SetlistAdvanceMode` (with associated
    /// values) and a simple Kind enum for the segmented control. The
    /// `.countdown` case carries a `measures: Int` parameter; the picker
    /// only flips the kind. Adjusting the measure count is a future detail
    /// surface — for now `.countdown` defaults to 1 measure.
    private enum AdvanceModeKind: String, Hashable {
        case pause, countdown, immediate
    }

    private var advanceModeKindBinding: Binding<AdvanceModeKind> {
        Binding(
            get: {
                switch setlist.advanceMode {
                case .pause: .pause
                case .countdown: .countdown
                case .immediate: .immediate
                }
            },
            set: { newKind in
                switch newKind {
                case .pause: setlist.advanceMode = .pause
                case .countdown:
                    // Restore the last-known countdown count instead of
                    // resetting to 1 — so toggling pause → countdown keeps
                    // the user's previously-set 2 or 4.
                    setlist.advanceMode = .countdown(measures: lastCountdownMeasures)
                case .immediate: setlist.advanceMode = .immediate
                }
                onSave(setlist)
            }
        )
    }

    private var advanceModeFooter: String {
        switch setlist.advanceMode {
        case .pause:
            "Stop after each song; tap Play to start the next."
        case .countdown(let m):
            "Auto-advance after a \(m)-measure count-off at the next song's tempo."
        case .immediate:
            "Jump straight into the next song on the last beat."
        }
    }

    // MARK: - Songs

    private var songsSection: some View {
        Section {
            if setlist.songs.isEmpty {
                Text("No songs yet. Tap + to add some.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.DSColor.textMuted)
                    .listRowBackground(DS.DSColor.bgElevated)
            } else {
                ForEach(setlist.songs) { song in
                    Button {
                        onSelectSong(song)
                    } label: {
                        songRow(song)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(DS.DSColor.bgElevated)
                }
                .onMove { indices, newOffset in
                    setlist.songs.move(fromOffsets: indices, toOffset: newOffset)
                    onSave(setlist)
                }
                .onDelete { indices in
                    setlist.songs.remove(atOffsets: indices)
                    onSave(setlist)
                }
            }
        } header: {
            Text("Songs (\(setlist.songs.count))")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private func songRow(_ song: Song) -> some View {
        HStack(spacing: DS.Spacing.md) {
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
    NavigationStack {
        SetlistDetailView(
            setlist: Setlist(name: "Tonight"),
            availableSongs: [],
            onSave: { _ in },
            onSelectSong: { _ in },
            onPlay: { _ in }
        )
    }
}
