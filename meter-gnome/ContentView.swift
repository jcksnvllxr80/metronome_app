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
    let viewModel: MetronomeViewModel
    @State private var showTimeSigPicker = false
    @State private var showSettings = false
    @State private var showLibrary = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 280 on iPad / large landscape; 180 on iPhone portrait. A first-pass
    /// alternative to true viewport-relative scaling — DESIGN.md asks for
    /// Stage BPM to fill ~55% of viewport height, which this approximates
    /// at common form factors. Full GeometryReader-driven scaling lands
    /// when the spec §10.3 "Large display mode" setting comes online.
    private var bpmFontSize: CGFloat {
        horizontalSizeClass == .regular ? 280 : 180
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.DSColor.bgBase.ignoresSafeArea()

            // TimelineView re-evaluates the body at the animation frame rate
            // so the pulse + active beat dot + tap flash track the engine
            // clock smoothly. When isRunning is false, pulseIntensity short-
            // circuits to 0 — body still re-runs every frame but most paths
            // are no-ops.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                let now = SystemClock().now
                content(at: now)
            }

            // Top overlay row — Library (leading) and Settings (trailing),
            // balanced around the centered time signature in the content
            // stack. Both icons are small + muted so they recede during
            // performance and DESIGN.md's 5-element rule applies in spirit.
            HStack {
                libraryButton
                Spacer()
                settingsButton
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTimeSigPicker) {
            TimeSignaturePickerView(current: viewModel.timeSignature) { selected in
                viewModel.setTimeSignature(selected)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(initial: viewModel.settings) { updated in
                viewModel.setSettings(updated)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(viewModel: viewModel)
                .presentationDetents([.large])
        }
    }

    private var libraryButton: some View {
        Button {
            viewModel.refreshLibrary()
            showLibrary = true
        } label: {
            Image(systemName: "music.note.list")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(DS.DSColor.textMuted)
                .padding(DS.Spacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Library")
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(DS.DSColor.textMuted)
                .padding(DS.Spacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    @ViewBuilder
    private func content(at now: TimeInterval) -> some View {
        let pulse = viewModel.pulseIntensity(at: now, reduceMotion: reduceMotion)
        let activeBeat = viewModel.currentClick(at: now)?.beatIndex
        let tapFlash = viewModel.tapFlashIntensity(at: now)

        VStack(spacing: 0) {
            // "Now playing setlist" strip, shown only when a setlist is active.
            // Above the time signature, mono small caps so it reads as
            // metadata rather than competing with the BPM hero.
            if viewModel.playingSetlistName != nil {
                setlistIndicator
                    .padding(.top, DS.Spacing.md)
            }

            timeSignatureButton
                .padding(.top, viewModel.playingSetlistName == nil ? DS.Spacing.lg : DS.Spacing.xs)

            Spacer()

            bpmView(pulse: pulse)

            Spacer()

            VStack(spacing: DS.Spacing.lg) {
                beatDotsView(activeBeat: activeBeat)
                controlsView
                tapButtonView(flash: tapFlash)
            }
            .padding(.bottom, DS.Spacing.xxl)
        }
    }

    // MARK: - Setlist indicator

    private var setlistIndicator: some View {
        Button {
            viewModel.stopSetlist()
        } label: {
            VStack(spacing: DS.Spacing.xxs) {
                Text(setlistTopLine)
                    .font(DS.Font.label)
                    .foregroundStyle(DS.DSColor.textMuted)
                    .textCase(.uppercase)
                    .tracking(2)
                if let title = viewModel.playingSongTitle {
                    Text(title)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.DSColor.textPrimary)
                }
                if viewModel.isWaitingForResume {
                    Text("Tap Play to continue")
                        .font(DS.Font.monoData)
                        .foregroundStyle(DS.DSColor.accentTempo)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.DSColor.bgElevated)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Setlist: \(viewModel.playingSetlistName ?? ""), song \(viewModel.playingSongIndex + 1) of \(viewModel.playingSetlistCount). Tap to exit setlist.")
    }

    private var setlistTopLine: String {
        let name = viewModel.playingSetlistName ?? ""
        let n = viewModel.playingSongIndex + 1
        let total = viewModel.playingSetlistCount
        return "\(name) · \(n) of \(total)"
    }

    // MARK: - Time signature (top, tap to open picker)

    private var timeSignatureButton: some View {
        Button {
            showTimeSigPicker = true
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text("\(viewModel.timeSignature.numerator)")
                Text("/").foregroundStyle(DS.DSColor.textDim)
                Text("\(viewModel.timeSignature.denominator.rawValue)")
            }
            .font(DS.Font.display)
            .monospacedDigit()
            .foregroundStyle(DS.DSColor.textPrimary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Time signature, \(viewModel.timeSignature.numerator) over \(viewModel.timeSignature.denominator.rawValue). Tap to change.")
    }

    // MARK: - BPM hero

    private func bpmView(pulse: Double) -> some View {
        let digitColor = viewModel.isRunning
            ? DS.DSColor.textPrimary.mix(with: DS.DSColor.accentTempo, by: pulse)
            : DS.DSColor.textPrimary

        return VStack(spacing: DS.Spacing.sm) {
            Text("\(viewModel.bpm.displayInt)")
                .font(.custom("JetBrainsMono-Bold", size: bpmFontSize))
                .monospacedDigit()
                .tracking(-bpmFontSize * 0.022)  // ~ -2% per DESIGN.md
                .foregroundStyle(digitColor)
                .contentTransition(.numericText(value: Double(viewModel.bpm.displayInt)))
                .animation(.snappy(duration: 0.15), value: viewModel.bpm.displayInt)
                .accessibilityLabel("Tempo, \(viewModel.bpm.displayInt) BPM")
            Text("BPM")
                .font(DS.Font.label)
                .foregroundStyle(DS.DSColor.textMuted)
                .textCase(.uppercase)
                .tracking(2)
                .accessibilityHidden(true)
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

    private func tapButtonView(flash: Double) -> some View {
        // 150 ms vermillion flash on each tap, fading linearly. Provides the
        // "visual feedback per tap" the spec §6.1 requires.
        let bgColor = DS.DSColor.bgElevated.mix(with: DS.DSColor.accentTempo, by: flash * 0.6)
        let textColor = DS.DSColor.textMuted.mix(with: DS.DSColor.textPrimary, by: flash)

        return Button {
            viewModel.tap()
        } label: {
            Text("TAP")
                .font(DS.Font.label)
                .tracking(2)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .background(bgColor, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Spacing.xxl)
        .accessibilityLabel("Tap tempo")
    }
}

#Preview {
    ContentView(viewModel: MetronomeViewModel())
}
