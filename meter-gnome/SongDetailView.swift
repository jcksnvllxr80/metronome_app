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
                accentPatternSection
                automationSection
                sectionsSection
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
            // Secondary action — enables the drag handles on the
            // multi-section and tempo-loop lists. Visible always so
            // users can tell reorder is available; no-op when neither
            // list has > 1 item.
            ToolbarItem(placement: .secondaryAction) {
                EditButton()
                    .foregroundStyle(DS.DSColor.accentTempo)
            }
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

    // MARK: - Accent Pattern

    private var accentPatternSection: some View {
        Section {
            NavigationLink {
                AccentPatternEditView(
                    timeSignature: song.timeSignature,
                    current: song.accentPattern,
                    viewModel: viewModel
                ) { newPattern in
                    // setAccentPattern enforces TS scoping (returns false
                    // on mismatch). The editor's pattern is built from
                    // song.timeSignature, so it always matches.
                    _ = song.setAccentPattern(newPattern)
                }
            } label: {
                HStack {
                    Text("Pattern")
                        .foregroundStyle(DS.DSColor.textPrimary)
                    Spacer()
                    Text(accentPatternSummary)
                        .font(DS.Font.body)
                        .foregroundStyle(accentPatternColor)
                }
            }
            .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("Accent Pattern").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Customize which beats in the measure are accented, muted, or softer.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var accentPatternSummary: String {
        song.accentPattern?.name ?? "Default (downbeat only)"
    }

    private var accentPatternColor: Color {
        song.accentPattern == nil ? DS.DSColor.textMuted : DS.DSColor.accentTempo
    }

    // MARK: - Tempo Automation (spec §6.3 gradual + §6.4 step)

    private enum AutomationKind: Hashable { case gradual, step, loop }
    private enum AutomationDurationKind: Hashable { case measures, seconds }

    private var automationSection: some View {
        Section {
            Toggle("Enable Automation", isOn: automationEnabledBinding)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)

            if let auto = song.automation {
                automationKindPicker(auto: auto)
                switch auto {
                case .gradual(let g):
                    gradualStartRow(g: g)
                    gradualEndRow(g: g)
                    gradualDurationKindRow(g: g)
                    gradualDurationValueRow(g: g)
                case .step(let s):
                    stepStartRow(s: s)
                    stepIncrementRow(s: s)
                    stepMeasuresPerStepRow(s: s)
                    stepCeilingRow(s: s)
                case .loop(let l):
                    loopStagesEditor(l: l)
                }
            }
        } header: {
            Text("Tempo Automation").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text(automationFooter).foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var automationEnabledBinding: Binding<Bool> {
        Binding(
            get: { song.automation != nil },
            // Toggling on defaults to gradual + 40 BPM ramp over 16 bars
            // (whichever direction current BPM allows). Step mode is
            // opt-in via the kind picker that appears once enabled.
            set: { isOn in
                if isOn {
                    let end = min(song.bpm.value + 40, BPM.maximum)
                    if let auto = TempoAutomation.gradual(
                        startBPM: song.bpm,
                        endBPM: BPM(end),
                        duration: .measures(16)
                    ) {
                        song.setAutomation(auto)
                    }
                } else {
                    song.setAutomation(nil)
                }
            }
        )
    }

    private func automationKindPicker(auto: TempoAutomation) -> some View {
        Picker(
            "Mode",
            selection: Binding<AutomationKind>(
                get: {
                    switch auto {
                    case .gradual: return .gradual
                    case .step: return .step
                    case .loop: return .loop
                    }
                },
                set: { newKind in
                    // Preserve startBPM across the kind switch; pick
                    // sensible defaults for the new case's other fields.
                    let start = auto.startBPM
                    switch newKind {
                    case .gradual:
                        if case .gradual = auto { return }
                        let end = min(start.value + 40, BPM.maximum)
                        if let next = TempoAutomation.gradual(
                            startBPM: start, endBPM: BPM(end), duration: .measures(16)
                        ) {
                            song.setAutomation(next)
                        }
                    case .step:
                        if case .step = auto { return }
                        if let next = TempoAutomation.step(
                            startBPM: start,
                            increment: 5,
                            measuresPerStep: 4,
                            ceiling: nil
                        ) {
                            song.setAutomation(next)
                        }
                    case .loop:
                        if case .loop = auto { return }
                        // Default loop: 2 stages — current BPM held for
                        // 4 measures, then +40 BPM held for 4 measures.
                        let other = BPM(min(start.value + 40, BPM.maximum))
                        if let next = TempoAutomation.loop(stages: [
                            .init(bpm: start, measures: 4),
                            .init(bpm: other, measures: 4),
                        ]) {
                            song.setAutomation(next)
                        }
                    }
                }
            )
        ) {
            Text("Gradual").tag(AutomationKind.gradual)
            Text("Step").tag(AutomationKind.step)
            Text("Loop").tag(AutomationKind.loop)
        }
        .pickerStyle(.segmented)
        .listRowBackground(DS.DSColor.bgElevated)
    }

    // MARK: Gradual rows

    private func gradualStartRow(g: TempoAutomation.Gradual) -> some View {
        Stepper(
            value: Binding(
                get: { g.startBPM.value },
                set: { v in
                    if let next = TempoAutomation.gradual(
                        startBPM: BPM(v), endBPM: g.endBPM, duration: g.duration
                    ) {
                        song.setAutomation(next)
                    }
                }
            ),
            in: BPM.minimum...BPM.maximum, step: 1
        ) {
            bpmRow(label: "Start BPM", value: g.startBPM)
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func gradualEndRow(g: TempoAutomation.Gradual) -> some View {
        Stepper(
            value: Binding(
                get: { g.endBPM.value },
                set: { v in
                    if let next = TempoAutomation.gradual(
                        startBPM: g.startBPM, endBPM: BPM(v), duration: g.duration
                    ) {
                        song.setAutomation(next)
                    }
                }
            ),
            in: BPM.minimum...BPM.maximum, step: 1
        ) {
            bpmRow(label: "End BPM", value: g.endBPM)
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func gradualDurationKindRow(g: TempoAutomation.Gradual) -> some View {
        Picker(
            "Duration",
            selection: Binding(
                get: {
                    switch g.duration {
                    case .measures: return AutomationDurationKind.measures
                    case .seconds: return AutomationDurationKind.seconds
                    }
                },
                set: { kind in
                    let newDuration: TempoAutomation.Duration
                    switch kind {
                    case .measures:
                        if case .measures = g.duration { return }
                        newDuration = .measures(16)
                    case .seconds:
                        if case .seconds = g.duration { return }
                        newDuration = .seconds(60)
                    }
                    if let next = TempoAutomation.gradual(
                        startBPM: g.startBPM, endBPM: g.endBPM, duration: newDuration
                    ) {
                        song.setAutomation(next)
                    }
                }
            )
        ) {
            Text("Measures").tag(AutomationDurationKind.measures)
            Text("Seconds").tag(AutomationDurationKind.seconds)
        }
        .pickerStyle(.segmented)
        .listRowBackground(DS.DSColor.bgElevated)
    }

    @ViewBuilder
    private func gradualDurationValueRow(g: TempoAutomation.Gradual) -> some View {
        switch g.duration {
        case .measures(let n):
            Stepper(value: Binding(
                get: { n },
                set: { newN in
                    if let next = TempoAutomation.gradual(
                        startBPM: g.startBPM, endBPM: g.endBPM, duration: .measures(newN)
                    ) {
                        song.setAutomation(next)
                    }
                }
            ), in: 1...512, step: 1) {
                intRow(label: "Measures", value: n)
            }
            .listRowBackground(DS.DSColor.bgElevated)
        case .seconds(let s):
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Text("Seconds").foregroundStyle(DS.DSColor.textPrimary)
                    Spacer()
                    Text("\(Int(s.rounded())) s")
                        .font(DS.Font.monoData)
                        .foregroundStyle(DS.DSColor.textPrimary)
                }
                Slider(value: Binding(
                    get: { s },
                    set: { newS in
                        if let next = TempoAutomation.gradual(
                            startBPM: g.startBPM, endBPM: g.endBPM,
                            duration: .seconds(newS.rounded())
                        ) {
                            song.setAutomation(next)
                        }
                    }
                ), in: 5...600, step: 1)
                    .tint(DS.DSColor.accentTempo)
            }
            .listRowBackground(DS.DSColor.bgElevated)
        }
    }

    // MARK: Step rows

    private func stepStartRow(s: TempoAutomation.Step) -> some View {
        Stepper(
            value: Binding(
                get: { s.startBPM.value },
                set: { v in
                    // Drop ceiling if the new start exceeds it (factory
                    // would otherwise reject the construction).
                    let newStart = BPM(v)
                    let newCeiling: BPM? = {
                        guard let c = s.ceiling else { return nil }
                        return c.value > newStart.value ? c : nil
                    }()
                    if let next = TempoAutomation.step(
                        startBPM: newStart, increment: s.increment,
                        measuresPerStep: s.measuresPerStep, ceiling: newCeiling
                    ) {
                        song.setAutomation(next)
                    }
                }
            ),
            in: BPM.minimum...BPM.maximum, step: 1
        ) {
            bpmRow(label: "Start BPM", value: s.startBPM)
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func stepIncrementRow(s: TempoAutomation.Step) -> some View {
        Stepper(
            value: Binding(
                get: { s.increment },
                set: { v in
                    if let next = TempoAutomation.step(
                        startBPM: s.startBPM, increment: max(1, v),
                        measuresPerStep: s.measuresPerStep, ceiling: s.ceiling
                    ) {
                        song.setAutomation(next)
                    }
                }
            ),
            in: 1...50, step: 1
        ) {
            HStack {
                Text("Increment").foregroundStyle(DS.DSColor.textPrimary)
                Spacer()
                Text("+\(Int(s.increment.rounded())) BPM")
                    .font(DS.Font.monoData)
                    .foregroundStyle(DS.DSColor.textPrimary)
            }
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func stepMeasuresPerStepRow(s: TempoAutomation.Step) -> some View {
        Stepper(value: Binding(
            get: { s.measuresPerStep },
            set: { newN in
                if let next = TempoAutomation.step(
                    startBPM: s.startBPM, increment: s.increment,
                    measuresPerStep: newN, ceiling: s.ceiling
                ) {
                    song.setAutomation(next)
                }
            }
        ), in: 1...64, step: 1) {
            intRow(label: "Measures per step", value: s.measuresPerStep)
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func stepCeilingRow(s: TempoAutomation.Step) -> some View {
        let ceilingEnabledBinding = Binding<Bool>(
            get: { s.ceiling != nil },
            set: { isOn in
                let newCeiling: BPM? = isOn
                    ? BPM(min(s.startBPM.value + s.increment * 8, BPM.maximum))
                    : nil
                if let next = TempoAutomation.step(
                    startBPM: s.startBPM, increment: s.increment,
                    measuresPerStep: s.measuresPerStep, ceiling: newCeiling
                ) {
                    song.setAutomation(next)
                }
            }
        )
        return Group {
            Toggle("Ceiling", isOn: ceilingEnabledBinding)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)
            if let ceiling = s.ceiling {
                Stepper(
                    value: Binding(
                        get: { ceiling.value },
                        set: { v in
                            // Ceiling must remain above startBPM; if user
                            // drives it down past start, snap it just above.
                            let clamped = max(s.startBPM.value + 1, v)
                            if let next = TempoAutomation.step(
                                startBPM: s.startBPM, increment: s.increment,
                                measuresPerStep: s.measuresPerStep,
                                ceiling: BPM(clamped)
                            ) {
                                song.setAutomation(next)
                            }
                        }
                    ),
                    in: BPM.minimum...BPM.maximum, step: 1
                ) {
                    bpmRow(label: "Ceiling BPM", value: ceiling)
                }
                .listRowBackground(DS.DSColor.bgElevated)
            }
        }
    }

    // MARK: Loop stages editor

    @ViewBuilder
    private func loopStagesEditor(l: TempoAutomation.Loop) -> some View {
        ForEach(Array(l.stages.enumerated()), id: \.offset) { idx, stage in
            loopStageRow(l: l, index: idx, stage: stage)
        }
        .onMove { source, destination in
            reorderLoopStages(l: l, from: source, to: destination)
        }
        Button {
            // Append a new stage cloning the last stage's BPM and 4
            // measures by default.
            var newStages = l.stages
            let last = newStages.last!
            newStages.append(.init(bpm: last.bpm, measures: 4))
            if let next = TempoAutomation.loop(stages: newStages) {
                song.setAutomation(next)
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add stage")
            }
            .foregroundStyle(DS.DSColor.accentTempo)
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func loopStageRow(l: TempoAutomation.Loop, index: Int, stage: TempoAutomation.Loop.Stage) -> some View {
        let canDelete = l.stages.count > 1
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text("Stage \(index + 1)")
                    .font(DS.Font.label)
                    .tracking(2)
                    .foregroundStyle(DS.DSColor.textMuted)
                Spacer()
                if canDelete {
                    Button(role: .destructive) {
                        var stages = l.stages
                        stages.remove(at: index)
                        if let next = TempoAutomation.loop(stages: stages) {
                            song.setAutomation(next)
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(DS.DSColor.accentTempo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete stage \(index + 1)")
                }
            }
            Stepper(
                value: Binding(
                    get: { stage.bpm.value },
                    set: { v in
                        var stages = l.stages
                        stages[index] = .init(bpm: BPM(v), measures: stage.measures)
                        if let next = TempoAutomation.loop(stages: stages) {
                            song.setAutomation(next)
                        }
                    }
                ),
                in: BPM.minimum...BPM.maximum, step: 1
            ) {
                bpmRow(label: "BPM", value: stage.bpm)
            }
            Stepper(
                value: Binding(
                    get: { stage.measures },
                    set: { v in
                        var stages = l.stages
                        stages[index] = .init(bpm: stage.bpm, measures: v)
                        if let next = TempoAutomation.loop(stages: stages) {
                            song.setAutomation(next)
                        }
                    }
                ),
                in: 1...64, step: 1
            ) {
                intRow(label: "Measures", value: stage.measures)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func reorderLoopStages(l: TempoAutomation.Loop, from source: IndexSet, to destination: Int) {
        var stages = l.stages
        stages.move(fromOffsets: source, toOffset: destination)
        // Empty-stages is structurally impossible after a move (count is
        // preserved), so the factory should never reject here — guard
        // defensively anyway.
        if let next = TempoAutomation.loop(stages: stages) {
            song.setAutomation(next)
        }
    }

    // MARK: Row helpers

    private func bpmRow(label: String, value: BPM, prefix: String = "") -> some View {
        HStack {
            Text(label).foregroundStyle(DS.DSColor.textPrimary)
            Spacer()
            Text("\(prefix)\(value.displayInt)")
                .font(DS.Font.monoData)
                .foregroundStyle(DS.DSColor.textPrimary)
        }
    }

    private func intRow(label: String, value: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(DS.DSColor.textPrimary)
            Spacer()
            Text("\(value)")
                .font(DS.Font.monoData)
                .foregroundStyle(DS.DSColor.textPrimary)
        }
    }

    private var automationFooter: String {
        guard let auto = song.automation else {
            return "Gradual ramps tempo linearly (accelerando / ritardando). Step jumps BPM by a fixed amount every N measures — useful for speed-trainer drills. Loop cycles through a sequence of tempos forever. All begin after count-in. Song tempo is locked to Start BPM while automation is enabled."
        }
        switch auto {
        case .gradual(let g):
            let direction = g.endBPM > g.startBPM ? "Accelerate" :
                            (g.endBPM < g.startBPM ? "Decelerate" : "Hold")
            let durationText: String
            switch g.duration {
            case .measures(let n): durationText = "\(n) measure\(n == 1 ? "" : "s")"
            case .seconds(let s): durationText = "\(Int(s.rounded())) seconds"
            }
            return "\(direction) from \(g.startBPM.displayInt) to \(g.endBPM.displayInt) BPM over \(durationText)."
        case .step(let s):
            let ceilingText = s.ceiling.map { ", stopping at \($0.displayInt) BPM" } ?? " (no ceiling — runs indefinitely)"
            return "Step up \(Int(s.increment.rounded())) BPM every \(s.measuresPerStep) measure\(s.measuresPerStep == 1 ? "" : "s") starting from \(s.startBPM.displayInt) BPM\(ceilingText)."
        case .loop(let l):
            let stageDesc = l.stages.map { "\($0.bpm.displayInt)·\($0.measures)m" }.joined(separator: " → ")
            return "Cycle through \(l.stages.count) stage\(l.stages.count == 1 ? "" : "s") indefinitely: \(stageDesc). Each stage holds at the given BPM for the given number of measures, then advances to the next."
        }
    }

    // MARK: - Sections (spec §7.3 multi-section songs)

    private var sectionsSection: some View {
        Section {
            Toggle("Multi-section song", isOn: sectionsEnabledBinding)
                .tint(DS.DSColor.accentTempo)
                .listRowBackground(DS.DSColor.bgElevated)

            if let sections = song.sections {
                ForEach(Array(sections.enumerated()), id: \.element.id) { idx, section in
                    sectionRow(index: idx, section: section, total: sections.count)
                }
                .onMove { source, destination in
                    reorderSections(from: source, to: destination)
                }
                Button {
                    addSection()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add section")
                    }
                    .foregroundStyle(DS.DSColor.accentTempo)
                }
                .listRowBackground(DS.DSColor.bgElevated)
            }
        } header: {
            Text("Sections").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text(sectionsFooter).foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var sectionsEnabledBinding: Binding<Bool> {
        Binding(
            get: { song.isMultiSection },
            set: { isOn in
                if isOn {
                    // Seed with one section cloned from the song's
                    // current flat tempo + meter so the user sees a
                    // sensible starting point.
                    if let first = SongSection(
                        name: "Intro",
                        bpm: song.bpm,
                        timeSignature: song.timeSignature,
                        subdivision: song.subdivision,
                        measureCount: 16
                    ) {
                        song.sections = [first]
                    }
                } else {
                    song.sections = nil
                }
            }
        )
    }

    private func sectionRow(index: Int, section: SongSection, total: Int) -> some View {
        let canDelete = total > 1
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("Section \(index + 1)")
                    .font(DS.Font.label)
                    .tracking(2)
                    .foregroundStyle(DS.DSColor.textMuted)
                Spacer()
                if canDelete {
                    Button(role: .destructive) {
                        deleteSection(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(DS.DSColor.accentTempo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete section \(index + 1)")
                }
            }
            TextField(
                "Name (optional)",
                text: Binding(
                    get: { section.name ?? "" },
                    set: { newValue in
                        updateSection(at: index) { s in
                            s.name = newValue.isEmpty ? nil : newValue
                        }
                    }
                )
            )
            .textInputAutocapitalization(.words)
            Stepper(
                value: Binding(
                    get: { section.bpm.value },
                    set: { v in
                        updateSection(at: index) { $0.bpm = BPM(v) }
                    }
                ),
                in: BPM.minimum...BPM.maximum, step: 1
            ) {
                bpmRow(label: "BPM", value: section.bpm)
            }
            Stepper(
                value: Binding(
                    get: { section.measureCount },
                    set: { v in
                        updateSection(at: index) { $0.measureCount = max(1, v) }
                    }
                ),
                in: 1...512, step: 1
            ) {
                intRow(label: "Measures", value: section.measureCount)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func updateSection(at index: Int, mutate: (inout SongSection) -> Void) {
        guard var sections = song.sections, sections.indices.contains(index) else { return }
        var copy = sections[index]
        mutate(&copy)
        sections[index] = copy
        song.sections = sections
    }

    private func addSection() {
        var sections = song.sections ?? []
        // Default new section: clones the last section's settings + 16 measures
        // so the user has a sensible starting point.
        let template = sections.last
        if let s = SongSection(
            name: nil,
            bpm: template?.bpm ?? song.bpm,
            timeSignature: template?.timeSignature ?? song.timeSignature,
            subdivision: template?.subdivision ?? song.subdivision,
            measureCount: 16
        ) {
            sections.append(s)
            song.sections = sections
        }
    }

    private func deleteSection(at index: Int) {
        guard var sections = song.sections, sections.indices.contains(index) else { return }
        sections.remove(at: index)
        song.sections = sections.isEmpty ? nil : sections
    }

    private func reorderSections(from source: IndexSet, to destination: Int) {
        guard var sections = song.sections else { return }
        sections.move(fromOffsets: source, toOffset: destination)
        song.sections = sections
    }

    private var sectionsFooter: String {
        if !song.isMultiSection {
            return "Multi-section songs play through a sequence of named sections (intro, verse, bridge…) each with their own BPM and measure count. The metronome auto-advances at the end of each section."
        }
        let total = song.sections?.reduce(0) { $0 + $1.measureCount } ?? 0
        return "\(song.sections?.count ?? 0) section\(song.sections?.count == 1 ? "" : "s"), \(total) measure\(total == 1 ? "" : "s") total. Plays in order from top to bottom, then stops."
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
