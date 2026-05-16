//
//  SongDetailView.swift
//  meter-gnome
//
//  Edit screen for a saved song. Pushed from the Library Songs tab.
//  Editable: title, duration (off / measures / seconds), notes.
//  Read-only: BPM / time signature / subdivision — those have their own
//  pickers on Stage; to change them, load the song, adjust on Stage, then
//  re-save (future commit: "Save Stage state back to this song").
//
//  Saves on every change via `onSave`. The Load button in the nav bar
//  applies the song to the engine and dismisses back to Stage.
//

import SwiftUI
import MetronomeCore

struct SongDetailView: View {
    @State var song: Song
    let viewModel: MetronomeViewModel
    let onSave: (Song) -> Void
    let onDelete: (UUID) -> Void
    let onLoad: (Song) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DS.DSColor.bgBase.ignoresSafeArea()
            Form {
                titleSection
                tempoSection
                matchStageSection
                soundSection
                durationSection
                notesSection
                deleteSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Song")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onLoad(song)
                    dismiss()
                } label: {
                    Label("Load", systemImage: "play.fill")
                }
                .foregroundStyle(DS.DSColor.accentTempo)
            }
        }
        .toolbarBackground(DS.DSColor.bgBase, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: song) { _, newValue in
            onSave(newValue)
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        Section {
            TextField("Song title", text: $song.title)
                .textInputAutocapitalization(.words)
                .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Title").foregroundStyle(DS.DSColor.textMuted)
        }
    }

    // MARK: - Tempo (read-only)

    private var tempoSection: some View {
        Section {
            metaRow(label: "Tempo", value: "\(song.bpm.displayInt) BPM")
            metaRow(label: "Time signature",
                    value: "\(song.timeSignature.numerator)/\(song.timeSignature.denominator.rawValue)")
            metaRow(label: "Subdivision",
                    value: SubdivisionLabel.descriptive(song.subdivision))
        } header: {
            Text("Tempo & Meter").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("To change tempo or meter, tap Load and adjust on Stage.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(DS.DSColor.textPrimary)
            Spacer()
            Text(value)
                .font(DS.Font.monoData)
                .foregroundStyle(DS.DSColor.textMuted)
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    // MARK: - Match Stage

    /// Section that surfaces what's currently set on Stage and lets the
    /// user write those values back to this song. Disabled when the song
    /// already matches Stage (nothing to apply).
    private var matchStageSection: some View {
        Section {
            metaRow(label: "Stage tempo", value: "\(viewModel.bpm.displayInt) BPM")
            metaRow(label: "Stage time signature",
                    value: "\(viewModel.timeSignature.numerator)/\(viewModel.timeSignature.denominator.rawValue)")
            metaRow(label: "Stage subdivision",
                    value: SubdivisionLabel.descriptive(viewModel.subdivision))
            Button {
                applyStageState()
            } label: {
                Text(songMatchesStage ? "Already Matches Stage" : "Apply Stage State")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(songMatchesStage ? DS.DSColor.textMuted : DS.DSColor.accentTempo)
            }
            .disabled(songMatchesStage)
            .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Match Stage").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Replace this song's tempo, time signature, and subdivision with the values currently on Stage. Notes, title, and duration are unchanged.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var songMatchesStage: Bool {
        song.bpm == viewModel.bpm
            && song.timeSignature == viewModel.timeSignature
            && song.subdivision == viewModel.subdivision
    }

    private func applyStageState() {
        song.bpm = viewModel.bpm
        // setTimeSignature is the safe mutator — it clears any accent
        // pattern scoped to the old meter, preserving the spec §3.2
        // invariant. Direct assignment to `timeSignature` won't compile
        // (private(set)) and wouldn't run that check anyway.
        song.setTimeSignature(viewModel.timeSignature)
        song.subdivision = viewModel.subdivision
        // onChange(of: song) will fire and trigger onSave.
    }

    // MARK: - Sound

    /// Bindings into `song.soundPreset` (a `String?`). The picker
    /// surfaces "Default" (nil) plus every `ClickSound` case; selecting
    /// "Default" clears the override and the engine falls back to the
    /// global setting at refill time.
    private var soundSection: some View {
        Section {
            Picker("Click Sound", selection: songSoundBinding) {
                Text("Default (Settings)").tag(String?.none)
                ForEach(ClickSound.allCases, id: \.self) { sound in
                    Text(sound.displayName).tag(String?.some(sound.rawValue))
                }
            }
            .pickerStyle(.menu)
            .tint(DS.DSColor.accentTempo)
            .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Sound").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Override the global click sound just for this song. Audible the next time this song is loaded.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var songSoundBinding: Binding<String?> {
        Binding(
            get: { song.soundPreset },
            set: { song.soundPreset = $0 }
        )
    }

    // MARK: - Duration

    private enum DurationKind: Hashable {
        case off, measures, seconds
    }

    private var currentDurationKind: DurationKind {
        switch song.duration {
        case .none: .off
        case .measures: .measures
        case .seconds: .seconds
        }
    }

    private var durationSection: some View {
        Section {
            Picker("Type", selection: durationKindBinding) {
                Text("Off").tag(DurationKind.off)
                Text("Measures").tag(DurationKind.measures)
                Text("Seconds").tag(DurationKind.seconds)
            }
            .pickerStyle(.segmented)
            .listRowBackground(DS.DSColor.bgElevated)

            durationValueRow
        } header: {
            Text("Auto-stop Duration").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text(durationFooter).foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var durationKindBinding: Binding<DurationKind> {
        Binding(
            get: { currentDurationKind },
            set: { newKind in
                switch newKind {
                case .off:
                    song.duration = nil
                case .measures:
                    // Preserve a previous measures count when toggling
                    // back; default to 16 bars (a common phrase length).
                    if case .measures = song.duration { /* keep */ }
                    else { song.duration = .measures(16) }
                case .seconds:
                    if case .seconds = song.duration { /* keep */ }
                    else { song.duration = .seconds(60) }
                }
            }
        )
    }

    @ViewBuilder
    private var durationValueRow: some View {
        switch song.duration {
        case .measures(let n):
            Stepper(value: Binding(
                get: { n },
                set: { song.duration = .measures($0) }
            ), in: 1...512, step: 1) {
                HStack {
                    Text("Measures")
                        .foregroundStyle(DS.DSColor.textPrimary)
                    Spacer()
                    Text("\(n)")
                        .font(DS.Font.monoData)
                        .foregroundStyle(DS.DSColor.textPrimary)
                }
            }
            .listRowBackground(DS.DSColor.bgElevated)
        case .seconds(let s):
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Text("Duration")
                        .foregroundStyle(DS.DSColor.textPrimary)
                    Spacer()
                    Text("\(Int(s.rounded())) s")
                        .font(DS.Font.monoData)
                        .foregroundStyle(DS.DSColor.textPrimary)
                }
                Slider(value: Binding(
                    get: { s },
                    set: { song.duration = .seconds($0.rounded()) }
                ), in: 5...600, step: 1)
                    .tint(DS.DSColor.accentTempo)
            }
            .listRowBackground(DS.DSColor.bgElevated)
        case nil:
            EmptyView()
        }
    }

    private var durationFooter: String {
        switch song.duration {
        case .none:
            "Plays until manually stopped. Doesn't auto-advance in setlists."
        case .measures(let n):
            "Auto-stops after \(n) measure\(n == 1 ? "" : "s"). Setlists use this to advance."
        case .seconds(let s):
            "Auto-stops after \(Int(s.rounded())) seconds."
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section {
            TextField(
                "Optional notes (capo, key, performance cues)",
                text: notesBinding,
                axis: .vertical
            )
            .lineLimit(3...8)
            .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Notes").foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { song.notes ?? "" },
            set: { song.notes = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                onDelete(song.id)
                dismiss()
            } label: {
                Text("Delete Song")
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(DS.DSColor.bgElevated)
        }
    }
}

#Preview {
    NavigationStack {
        SongDetailView(
            song: Song(title: "Wonderwall", bpm: BPM(87), duration: .measures(64))!,
            viewModel: MetronomeViewModel(),
            onSave: { _ in },
            onDelete: { _ in },
            onLoad: { _ in }
        )
    }
}
