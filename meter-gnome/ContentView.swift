//
//  ContentView.swift
//  meter-gnome
//
//  Stage view per DESIGN.md — composition-first poster with BPM as the
//  read-head, time signature above, beat indicator and play/stop + ±
//  controls + tap tempo below. Five top-level elements total. No audio yet
//  — the engine schedules clicks internally but doesn't produce sound. The
//  visual pulse drives off the engine's clock so it correlates exactly with
//  what audio will play once wired.
//

import SwiftUI
import MetronomeCore

struct ContentView: View {
    @State private var viewModel = MetronomeViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        ZStack {
            DS.DSColor.bgBase.ignoresSafeArea()

            // TimelineView re-evaluates the body at the animation frame rate
            // so the pulse + active beat dot track the engine clock smoothly.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                let now = SystemClock().now
                content(at: now)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(at now: TimeInterval) -> some View {
        let pulse = viewModel.pulseIntensity(at: now, reduceMotion: reduceMotion)
        let activeBeat = viewModel.currentClick(at: now)?.beatIndex

        VStack(spacing: 0) {
            timeSignatureView
                .padding(.top, DS.Spacing.lg)

            Spacer()

            bpmView(pulse: pulse)

            Spacer()

            VStack(spacing: DS.Spacing.lg) {
                beatDotsView(activeBeat: activeBeat)
                controlsView
                tapButtonView
            }
            .padding(.bottom, DS.Spacing.xxl)
        }
    }

    // MARK: - Time signature

    private var timeSignatureView: some View {
        HStack(spacing: DS.Spacing.xs) {
            Text("\(viewModel.timeSignature.numerator)")
            Text("/").foregroundStyle(DS.DSColor.textDim)
            Text("\(viewModel.timeSignature.denominator.rawValue)")
        }
        .font(DS.Font.display)
        .monospacedDigit()
        .foregroundStyle(DS.DSColor.textPrimary)
    }

    // MARK: - BPM hero

    private func bpmView(pulse: Double) -> some View {
        // Mix base ↔ accent by pulse intensity. iOS 18+ has Color.mix(with:by:).
        let digitColor = viewModel.isRunning
            ? DS.DSColor.textPrimary.mix(with: DS.DSColor.accentTempo, by: pulse)
            : DS.DSColor.textPrimary

        return VStack(spacing: DS.Spacing.sm) {
            Text("\(viewModel.bpm.displayInt)")
                .font(DS.Font.bpmHero)
                .monospacedDigit()
                .tracking(-4)
                .foregroundStyle(digitColor)
                .contentTransition(.numericText(value: Double(viewModel.bpm.displayInt)))
                .animation(.snappy(duration: 0.15), value: viewModel.bpm.displayInt)
            Text("BPM")
                .font(DS.Font.label)
                .foregroundStyle(DS.DSColor.textMuted)
                .textCase(.uppercase)
                .tracking(2)
        }
    }

    // MARK: - Beat dots

    private func beatDotsView(activeBeat: Int?) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(0..<viewModel.timeSignature.numerator, id: \.self) { i in
                let active = (i == activeBeat)
                let isDownbeat = (i == 0)
                Circle()
                    .fill(active ? DS.DSColor.accentTempo : DS.DSColor.textDim)
                    .frame(
                        width: isDownbeat ? 14 : 10,
                        height: isDownbeat ? 14 : 10
                    )
                    .accessibilityLabel(
                        active
                            ? "Beat \(i + 1) of \(viewModel.timeSignature.numerator), active"
                            : "Beat \(i + 1) of \(viewModel.timeSignature.numerator)"
                    )
            }
        }
        .animation(.snappy(duration: 0.08), value: activeBeat)
    }

    // MARK: - Controls

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
        .accessibilityLabel(delta < 0 ? "Decrease tempo" : "Increase tempo")
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
                .offset(x: viewModel.isRunning ? 0 : 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isRunning ? "Stop" : "Start")
    }

    // MARK: - Tap tempo

    private var tapButtonView: some View {
        Button {
            viewModel.tap()
        } label: {
            Text("TAP")
                .font(DS.Font.label)
                .tracking(2)
                .foregroundStyle(DS.DSColor.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.DSColor.bgElevated, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Spacing.xxl)
        .accessibilityLabel("Tap tempo")
    }
}

#Preview {
    ContentView()
}
