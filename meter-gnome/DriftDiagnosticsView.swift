//
//  DriftDiagnosticsView.swift
//  meter-gnome
//
//  Settings → Diagnostics → Drift Self-Test sheet. Drives `DriftSelfTest`
//  and displays the result. Measurement-only — does not adjust any
//  engine state after the test. See DriftSelfTest.swift for the
//  measurement methodology.
//

import SwiftUI
import Charts

struct DriftDiagnosticsView: View {
    let test: DriftSelfTest

    @State private var phase: Phase = .idle
    @State private var result: DriftSelfTest.Result?
    @State private var elapsed: TimeInterval = 0
    @State private var progressTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case idle
        case running(duration: TimeInterval)
        case finished
    }

    /// Default test duration in seconds. 60s at 120 BPM is 120 clicks —
    /// plenty for a stable median-IOI estimate while keeping the UX
    /// short enough that the user actually completes the test.
    private let defaultDuration: TimeInterval = 60

    var body: some View {
        Form {
            descriptionSection
            actionSection
            if let r = result {
                resultSection(r)
                intervalChartSection(r)
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.DSColor.bgBase.ignoresSafeArea())
        .navigationTitle("Drift Self-Test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.DSColor.bgBase, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onDisappear {
            progressTask?.cancel()
        }
    }

    private var descriptionSection: some View {
        let intro = "Plays a steady stream of clicks at 120 BPM in 4/4 for \(Int(defaultDuration)) seconds, samples the audio before it leaves the device, and measures the actual click period to confirm it matches the scheduled period to within the spec §1.1 budget of 1 ms per minute."
        let caveats = "Tap Start, leave the app foregrounded, and don't press Play on Stage during the test. Engine state (BPM, time signature, subdivision, automation) is overwritten by the test; you may need to reload your song afterward."
        return Section {
            Text(intro)
                .font(DS.Font.body)
                .foregroundStyle(DS.DSColor.textMuted)
                .listRowBackground(DS.DSColor.bgElevated)
            Text(caveats)
                .font(DS.Font.label)
                .foregroundStyle(DS.DSColor.textDim)
                .listRowBackground(DS.DSColor.bgElevated)
        } header: {
            Text("How it works").foregroundStyle(DS.DSColor.textMuted)
        }
    }

    private var actionSection: some View {
        Section {
            switch phase {
            case .idle:
                Button {
                    runTest()
                } label: {
                    HStack {
                        Image(systemName: "stopwatch")
                        Text("Start \(Int(defaultDuration))-second test")
                            .font(DS.Font.headline)
                    }
                    .foregroundStyle(DS.DSColor.accentTempo)
                }
                .listRowBackground(DS.DSColor.bgElevated)
            case .running(let duration):
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack {
                        Text("Running…")
                            .font(DS.Font.headline)
                            .foregroundStyle(DS.DSColor.accentTempo)
                        Spacer()
                        Text(timeString(elapsed) + " / " + timeString(duration))
                            .font(DS.Font.monoData)
                            .foregroundStyle(DS.DSColor.textPrimary)
                    }
                    ProgressView(value: min(elapsed / duration, 1.0))
                        .tint(DS.DSColor.accentTempo)
                        .accessibilityLabel("Drift test progress")
                }
                .listRowBackground(DS.DSColor.bgElevated)
            case .finished:
                Button {
                    result = nil
                    phase = .idle
                } label: {
                    Text("Run again")
                        .foregroundStyle(DS.DSColor.accentTempo)
                }
                .listRowBackground(DS.DSColor.bgElevated)
            }
        }
    }

    @ViewBuilder
    private func resultSection(_ r: DriftSelfTest.Result) -> some View {
        let footerText = "Interval std-dev reflects onset-detection jitter, not engine drift. Values under ~1 ms indicate clean detection; higher numbers mean the drift figure has wider error bars."
        Section {
            verdictRow(r)
            statRow(
                label: "Measured drift",
                value: String(format: "%+.3f ms / min", r.driftMsPerMinute)
            )
            statRow(
                label: "Spec budget",
                value: String(format: "± %.1f ms / min", DriftSelfTest.specBudgetMsPerMinute)
            )
            statRow(
                label: "Expected period",
                value: String(format: "%.3f ms", r.expectedPeriodSeconds * 1000)
            )
            statRow(
                label: "Measured period (median)",
                value: String(format: "%.3f ms", r.measuredPeriodSeconds * 1000)
            )
            statRow(
                label: "Interval std-dev",
                value: String(format: "%.3f ms", r.intervalStdDevMs)
            )
            statRow(
                label: "Detected clicks",
                value: "\(r.detectedClickCount)"
            )
            statRow(
                label: "Test duration",
                value: String(format: "%.0f s", r.durationSeconds)
            )
            statRow(
                label: "Audio sample rate",
                value: String(format: "%.0f Hz", r.sampleRateHz)
            )
        } header: {
            Text("Result").foregroundStyle(DS.DSColor.textMuted)
        } footer: {
            Text(footerText).foregroundStyle(DS.DSColor.textMuted)
        }
    }

    @ViewBuilder
    private func intervalChartSection(_ r: DriftSelfTest.Result) -> some View {
        if !r.intervalsMs.isEmpty {
            let expectedMs = r.expectedPeriodSeconds * 1000
            let footer = "Each dot is one inter-onset interval. Flat line at the dashed reference = no drift. Sloped trend = real drift. Scatter above/below = onset-detection jitter (room ambience, click envelope edges). Outliers off the chart top/bottom are missed or spurious detections that the median + std-dev exclude."
            Section {
                Chart {
                    RuleMark(y: .value("Expected", expectedMs))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(DS.DSColor.textDim)
                    ForEach(Array(r.intervalsMs.enumerated()), id: \.offset) { idx, ms in
                        PointMark(
                            x: .value("Click", idx + 1),
                            y: .value("Interval", ms)
                        )
                        .foregroundStyle(DS.DSColor.accentTempo)
                        .symbolSize(20)
                    }
                }
                .chartYAxisLabel("Interval (ms)")
                .chartXAxisLabel("Click index")
                .frame(height: 220)
                .listRowBackground(DS.DSColor.bgElevated)
                .accessibilityLabel("Inter-onset interval plot")
                .accessibilityValue("\(r.intervalsMs.count) intervals plotted, expected \(String(format: "%.0f", expectedMs)) ms")
            } header: {
                Text("Inter-onset intervals").foregroundStyle(DS.DSColor.textMuted)
            } footer: {
                Text(footer).foregroundStyle(DS.DSColor.textMuted)
            }
        }
    }

    private func verdictRow(_ r: DriftSelfTest.Result) -> some View {
        HStack {
            Image(systemName: r.withinSpec ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(r.withinSpec ? DS.DSColor.textPrimary : DS.DSColor.accentTempo)
            Text(r.withinSpec ? "Within spec" : "Exceeds spec")
                .font(DS.Font.headline)
                .foregroundStyle(DS.DSColor.textPrimary)
            Spacer()
        }
        .listRowBackground(DS.DSColor.bgElevated)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            r.withinSpec
                ? "Result: within spec, drift \(String(format: "%.2f", r.driftMsPerMinute)) ms per minute"
                : "Result: exceeds spec, drift \(String(format: "%.2f", r.driftMsPerMinute)) ms per minute"
        )
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(DS.DSColor.textPrimary)
            Spacer()
            Text(value)
                .font(DS.Font.monoData)
                .foregroundStyle(DS.DSColor.textMuted)
        }
        .listRowBackground(DS.DSColor.bgElevated)
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - Actions

    private func runTest() {
        let duration = defaultDuration
        phase = .running(duration: duration)
        elapsed = 0
        result = nil

        // Drive the progress bar in parallel with the test run.
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let now = Date().timeIntervalSince(start)
                if now > duration { break }
                elapsed = now
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            elapsed = duration
        }

        Task { @MainActor in
            let r = await test.run(bpm: 120, duration: duration)
            progressTask?.cancel()
            elapsed = duration
            result = r
            phase = .finished
        }
    }
}
