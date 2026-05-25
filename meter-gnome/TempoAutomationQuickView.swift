//
//  TempoAutomationQuickView.swift
//  meter-gnome
//
//  Stage quick-action sheet for tempo automation (spec §6.3 stage-
//  quick-sheet variant). Lets users configure a gradual ramp without
//  having to save a song first — the most common automation use case
//  ("accel from 90 to 120 over 32 bars") shouldn't require library
//  ceremony. Step + loop modes remain in SongDetailView since their
//  controls deserve a full-form editor and they're more typically
//  attached to a specific tune.
//
//  Behavior:
//  - Initial state seeded from viewModel.automation (if a gradual
//    ramp is active) or from viewModel.bpm + a sensible 40-BPM-up
//    default span.
//  - Apply commits via viewModel.setAutomation(_:). Engine auto-pins
//    BPM to startBPM whenever automation is non-nil.
//  - Clear nils out any active automation.
//

import SwiftUI
import MetronomeCore

struct TempoAutomationQuickView: View {
    @Bindable var viewModel: MetronomeViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var startBPM: Int
    @State private var endBPM: Int
    @State private var durationKind: DurationKind
    @State private var durationMeasures: Int
    @State private var durationSeconds: Int

    private enum DurationKind: Hashable { case measures, seconds }

    init(viewModel: MetronomeViewModel) {
        self.viewModel = viewModel
        // Seed from active gradual automation when present, otherwise
        // from Stage BPM + a +40 default end (clamped to BPM max).
        if case .gradual(let g) = viewModel.automation {
            self._startBPM = State(initialValue: g.startBPM.displayInt)
            self._endBPM = State(initialValue: g.endBPM.displayInt)
            switch g.duration {
            case .measures(let n):
                self._durationKind = State(initialValue: .measures)
                self._durationMeasures = State(initialValue: n)
                self._durationSeconds = State(initialValue: 60)
            case .seconds(let s):
                self._durationKind = State(initialValue: .seconds)
                self._durationMeasures = State(initialValue: 16)
                self._durationSeconds = State(initialValue: Int(s.rounded()))
            }
        } else {
            let current = viewModel.bpm.displayInt
            let endDefault = min(current + 40, Int(BPM.maximum))
            self._startBPM = State(initialValue: current)
            self._endBPM = State(initialValue: endDefault)
            self._durationKind = State(initialValue: .measures)
            self._durationMeasures = State(initialValue: 16)
            self._durationSeconds = State(initialValue: 60)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.DSColor.bgBase.ignoresSafeArea()
                Form {
                    rampSection
                    durationSection
                    actionsSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Tempo Ramp")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.DSColor.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .foregroundStyle(DS.DSColor.accentTempo)
                        .disabled(!canApply)
                }
            }
            .compatBarBackground(DS.DSColor.bgBase)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var rampSection: some View {
        Section {
            bpmStepperRow(label: "Start BPM", value: $startBPM)
            bpmStepperRow(label: "End BPM", value: $endBPM)
        } header: {
            Text("Tempo Range").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text(rangeFooterText).foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var durationSection: some View {
        Section {
            Picker("Duration", selection: $durationKind) {
                Text("Measures").tag(DurationKind.measures)
                Text("Seconds").tag(DurationKind.seconds)
            }
            .pickerStyle(.segmented)
            .listRowBackground(DS.DSColor.bgElevated)

            switch durationKind {
            case .measures:
                Stepper(value: $durationMeasures, in: 1...256, step: 1) {
                    HStack {
                        Text("Measures").foregroundStyle(DS.DSColor.textPrimary)
                        Spacer()
                        Text("\(durationMeasures)")
                            .font(DS.Font.monoData)
                            .foregroundStyle(DS.DSColor.accentTempo)
                    }
                }
                .listRowBackground(DS.DSColor.bgElevated)
            case .seconds:
                Stepper(value: $durationSeconds, in: 5...3600, step: 5) {
                    HStack {
                        Text("Seconds").foregroundStyle(DS.DSColor.textPrimary)
                        Spacer()
                        Text("\(durationSeconds)")
                            .font(DS.Font.monoData)
                            .foregroundStyle(DS.DSColor.accentTempo)
                    }
                }
                .listRowBackground(DS.DSColor.bgElevated)
            }
        } header: {
            Text("Ramp Duration").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text("Measures use the current time signature. Seconds are wall-clock — count-in time isn't included if you start with a count-in.")
                .foregroundStyle(DS.DSColor.textMuted)
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            if viewModel.automation != nil {
                Button(role: .destructive) {
                    viewModel.setAutomation(nil)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "stop.circle")
                        Text("Clear Automation")
                    }
                }
                .listRowBackground(DS.DSColor.bgElevated)
            }
        }
    }

    // MARK: - Helpers

    private var canApply: Bool {
        startBPM != endBPM &&
        startBPM >= Int(BPM.minimum) && startBPM <= Int(BPM.maximum) &&
        endBPM >= Int(BPM.minimum) && endBPM <= Int(BPM.maximum)
    }

    private var rangeFooterText: String {
        if startBPM == endBPM {
            return "Set a different start and end BPM to enable Apply."
        }
        let direction = endBPM > startBPM ? "Accelerando" : "Ritardando"
        return "\(direction): \(startBPM) → \(endBPM) BPM. The Stage BPM will lock to \(startBPM) while the ramp is active. Press Stage's play to begin."
    }

    private func bpmStepperRow(label: String, value: Binding<Int>) -> some View {
        Stepper(
            value: value,
            in: Int(BPM.minimum)...Int(BPM.maximum),
            step: 1
        ) {
            HStack {
                Text(label).foregroundStyle(DS.DSColor.textPrimary)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(DS.Font.monoData)
                    .foregroundStyle(DS.DSColor.accentTempo)
            }
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func apply() {
        guard canApply else { return }
        let start = BPM(Double(startBPM))
        let end = BPM(Double(endBPM))
        let duration: TempoAutomation.Duration
        switch durationKind {
        case .measures:
            duration = .measures(durationMeasures)
        case .seconds:
            duration = .seconds(TimeInterval(durationSeconds))
        }
        guard let auto = TempoAutomation.gradual(
            startBPM: start,
            endBPM: end,
            duration: duration
        ) else { return }
        viewModel.setAutomation(auto)
        dismiss()
    }
}
