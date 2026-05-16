//
//  ContentView.swift
//  meter-gnome
//
//  Stage view per DESIGN.md — composition-first poster with BPM as the
//  read-head, time signature above, play/stop + ± controls below. Five
//  elements total. No audio yet — the engine schedules clicks internally
//  but doesn't produce sound. UI controls are functional end-to-end.
//

import SwiftUI
import MetronomeCore

struct ContentView: View {
    @State private var viewModel = MetronomeViewModel()

    var body: some View {
        ZStack {
            DS.DSColor.bgBase.ignoresSafeArea()
            VStack(spacing: 0) {
                timeSignatureView
                    .padding(.top, DS.Spacing.lg)
                Spacer()
                bpmView
                Spacer()
                controlsView
                    .padding(.bottom, DS.Spacing.xxl)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var timeSignatureView: some View {
        HStack(spacing: DS.Spacing.xs) {
            Text("\(viewModel.timeSignature.numerator)")
            Text("/")
                .foregroundStyle(DS.DSColor.textDim)
            Text("\(viewModel.timeSignature.denominator.rawValue)")
        }
        .font(DS.Font.display)
        .monospacedDigit()
        .foregroundStyle(DS.DSColor.textPrimary)
    }

    private var bpmView: some View {
        VStack(spacing: DS.Spacing.sm) {
            Text("\(viewModel.bpm.displayInt)")
                .font(DS.Font.bpmHero)
                .monospacedDigit()
                .tracking(-4)
                .foregroundStyle(viewModel.isRunning ? DS.DSColor.accentTempo : DS.DSColor.textPrimary)
                .contentTransition(.numericText(value: Double(viewModel.bpm.displayInt)))
                .animation(.snappy(duration: 0.15), value: viewModel.bpm.displayInt)
            Text("BPM")
                .font(DS.Font.label)
                .foregroundStyle(DS.DSColor.textMuted)
                .textCase(.uppercase)
                .tracking(2)
        }
    }

    private var controlsView: some View {
        HStack(spacing: DS.Spacing.xl) {
            nudgeButton(label: "minus", delta: -1)
            playStopButton
            nudgeButton(label: "plus", delta: 1)
        }
    }

    private func nudgeButton(label: String, delta: Double) -> some View {
        Button {
            viewModel.nudgeBPM(by: delta)
        } label: {
            Image(systemName: label)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(DS.DSColor.textPrimary)
                .frame(width: 56, height: 56)
                .background(DS.DSColor.bgElevated, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var playStopButton: some View {
        Button {
            viewModel.togglePlay()
        } label: {
            Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(viewModel.isRunning ? DS.DSColor.bgBase : DS.DSColor.textPrimary)
                .frame(width: 88, height: 88)
                .background(
                    Circle().fill(viewModel.isRunning ? DS.DSColor.accentTempo : DS.DSColor.bgElevated)
                )
                // Offset the play icon's optical center; stop is already centered.
                .offset(x: viewModel.isRunning ? 0 : 3)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
