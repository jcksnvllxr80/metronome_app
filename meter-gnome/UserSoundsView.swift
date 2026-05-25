//
//  UserSoundsView.swift
//  meter-gnome
//
//  Manage imported sounds (spec §4.2). Sheet-style drill-in opened
//  from Settings → Sound → Imported Sounds. Lists every sound in
//  the user sandbox, lets the user rename + retrim volume + delete,
//  and import a new file via UIDocumentPickerView (SwiftUI's
//  `.fileImporter`).
//

import SwiftUI
import UniformTypeIdentifiers
import MetronomeCore

struct UserSoundsView: View {
    @Bindable var viewModel: MetronomeViewModel

    @State private var showImporter: Bool = false
    @State private var errorMessage: String? = nil
    @State private var editingSound: UserSound? = nil

    /// Audio types the import picker accepts. Spec §4.2 explicitly
    /// lists WAV / AIFF / CAF. `.aiff` covers both `.aif` and `.aiff`
    /// extensions; CoreAudioFormat handles `.caf`.
    private static let importableTypes: [UTType] = [
        .wav,
        .aiff,
        UTType("com.apple.coreaudio-format") ?? .audio,
    ]

    var body: some View {
        Group {
            if viewModel.userSounds.isEmpty {
                emptyState
            } else {
                soundList
            }
        }
        .navigationTitle("Imported Sounds")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                }
                .foregroundStyle(DS.DSColor.accentTempo)
                .accessibilityLabel("Import sound")
            }
        }
        .compatBarBackground(DS.DSColor.bgBase)
        .background(DS.DSColor.bgBase.ignoresSafeArea())
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: Self.importableTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .alert(
            "Import failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            actions: { Button("OK", role: .cancel) { errorMessage = nil } },
            message: { Text(errorMessage ?? "") }
        )
        .sheet(item: $editingSound) { sound in
            NavigationStack {
                UserSoundEditView(initial: sound) { updated in
                    viewModel.updateUserSound(updated)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DS.DSColor.textDim)
            Text("No imported sounds yet")
                .font(DS.Font.headline)
                .foregroundStyle(DS.DSColor.textPrimary)
            Text("Tap + to import a WAV, AIFF, or CAF file. Limits: 2 seconds, 1 MB.")
                .font(DS.Font.body)
                .foregroundStyle(DS.DSColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xxl)
        }
    }

    private var soundList: some View {
        List {
            ForEach(viewModel.userSounds) { sound in
                Button {
                    editingSound = sound
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(sound.name)
                                .font(DS.Font.headline)
                                .foregroundStyle(DS.DSColor.textPrimary)
                            Text("Volume \(Int((sound.volumeTrim * 100).rounded()))%")
                                .font(DS.Font.monoData)
                                .foregroundStyle(DS.DSColor.textMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(DS.DSColor.textDim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(DS.DSColor.bgElevated)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteUserSound(id: sound.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Security-scoped resource access. The user picked a file
            // outside our sandbox; we need to start the scope before
            // reading + stop it after, even though the actual copy
            // happens synchronously inside importUserSound.
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            do {
                _ = try viewModel.importUserSound(from: url)
            } catch let error as UserSoundImportError {
                errorMessage = Self.message(for: error)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private static func message(for error: UserSoundImportError) -> String {
        switch error {
        case .unsupportedFormat:
            return "Only WAV, AIFF, and CAF files are supported."
        case .fileTooLarge(let bytes):
            let kib = Double(bytes) / 1024.0
            return String(format: "File is %.0f KiB — limit is 1024 KiB (1 MB).", kib)
        case .durationTooLong(let seconds):
            return String(format: "Clip is %.1f s — limit is 2 s.", seconds)
        case .couldNotDecode:
            return "Couldn't read that file as audio."
        case .fileSystem(let detail):
            return "File copy failed: \(detail)"
        }
    }
}

/// Sub-sheet for renaming + retrimming a single imported sound.
private struct UserSoundEditView: View {
    let initial: UserSound
    let onSave: (UserSound) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var volumeTrim: Double

    init(initial: UserSound, onSave: @escaping (UserSound) -> Void) {
        self.initial = initial
        self.onSave = onSave
        self._name = State(initialValue: initial.name)
        self._volumeTrim = State(initialValue: initial.volumeTrim)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .wordsAutocapitalization()
                    .listRowBackground(DS.DSColor.bgElevated)
            } header: {
                Text("Name").foregroundStyle(DS.DSColor.textMuted)
            }
            Section {
                HStack(spacing: DS.Spacing.md) {
                    Slider(value: $volumeTrim, in: 0...1)
                        .tint(DS.DSColor.accentTempo)
                        .accessibilityLabel("Volume trim")
                    Text("\(Int((volumeTrim * 100).rounded()))%")
                        .font(DS.Font.monoData)
                        .frame(width: 48, alignment: .trailing)
                        .foregroundStyle(DS.DSColor.textPrimary)
                }
                .listRowBackground(DS.DSColor.bgElevated)
            } header: {
                Text("Volume Trim").foregroundStyle(DS.DSColor.textMuted)
            } footer: {
                Text("Scales this sound's amplitude relative to the built-in clicks. Useful when an import is louder or quieter than the others.")
                    .foregroundStyle(DS.DSColor.textMuted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.DSColor.bgBase.ignoresSafeArea())
        .navigationTitle("Edit Sound")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(DS.DSColor.textMuted)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let updated = UserSound(
                        id: initial.id,
                        name: trimmed.isEmpty ? initial.name : trimmed,
                        filename: initial.filename,
                        volumeTrim: volumeTrim
                    )
                    onSave(updated)
                    dismiss()
                }
                .foregroundStyle(DS.DSColor.accentTempo)
            }
        }
        .compatBarBackground(DS.DSColor.bgBase)
    }
}
