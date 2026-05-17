//
//  StatsView.swift
//  meter-gnome
//
//  Practice-stats screen (spec §11). Reached via the Library sheet's
//  third segmented tab. Shows:
//   - Three time cards: today / this week / this month total practice.
//   - Per-song breakdown sorted by total time.
//   - CSV export via ShareLink + a Clear History destructive action.
//
//  All-time totals are intentionally not shown — that's a "vanity
//  metric" without a useful comparison frame. The three windows match
//  what musicians actually plan around (today's session, the
//  week's hours, the month's discipline trend).
//

import SwiftUI
import Charts
import MetronomeCore
import UniformTypeIdentifiers

struct StatsView: View {
    @Bindable var viewModel: MetronomeViewModel
    @State private var showClearConfirmation = false

    private var sessions: [PracticeSession] { viewModel.practiceSessions }

    var body: some View {
        ZStack {
            DS.DSColor.bgBase.ignoresSafeArea()
            if sessions.isEmpty {
                emptyState
            } else {
                scrollContent
            }
        }
        .onAppear {
            viewModel.refreshPracticeSessions()
        }
        .alert("Clear practice history?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                _ = viewModel.clearPracticeHistory()
            }
        } message: {
            Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") will be permanently deleted.")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(DS.DSColor.textDim)
            Text("No practice yet")
                .font(DS.Font.headline)
                .foregroundStyle(DS.DSColor.textPrimary)
            Text("Sessions longer than 30 seconds will show up here.")
                .font(DS.Font.body)
                .foregroundStyle(DS.DSColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                summaryCards
                dailyChart
                bySongSection
                actionsSection
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - Daily totals chart (last 14 days)

    private var dailyChart: some View {
        let totals = sessions.dailyTotals(forLast: 14)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("LAST 14 DAYS")
                .font(DS.Font.label)
                .tracking(2)
                .foregroundStyle(DS.DSColor.textMuted)
            Chart(totals, id: \.date) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Minutes", day.total / 60)
                )
                .foregroundStyle(DS.DSColor.accentTempo)
                .cornerRadius(DS.Radius.sm)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { value in
                    AxisValueLabel(format: .dateTime.day(.defaultDigits))
                        .foregroundStyle(DS.DSColor.textMuted)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(DS.DSColor.textDim.opacity(0.3))
                    AxisValueLabel()
                        .foregroundStyle(DS.DSColor.textMuted)
                }
            }
            .frame(height: 120)
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.DSColor.bgElevated)
            )
        }
    }

    // MARK: - Time-window cards

    private var summaryCards: some View {
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let startOfWeek = Calendar.current.date(
            from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? startOfToday
        let startOfMonth = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now)
        ) ?? startOfToday
        let goalMinutes = viewModel.settings.dailyPracticeGoalMinutes
        let todayTotal = sessions.started(onOrAfter: startOfToday).totalDuration
        return VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                timeCard(label: "Today", total: todayTotal)
                timeCard(label: "Week", total: sessions.started(onOrAfter: startOfWeek).totalDuration)
                timeCard(label: "Month", total: sessions.started(onOrAfter: startOfMonth).totalDuration)
            }
            if goalMinutes > 0 {
                goalProgressBar(todayMinutes: todayTotal / 60, goalMinutes: Double(goalMinutes))
            }
        }
    }

    private func timeCard(label: String, total: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(label.uppercased())
                .font(DS.Font.label)
                .tracking(2)
                .foregroundStyle(DS.DSColor.textMuted)
            Text(Self.formatDuration(total))
                .font(DS.Font.monoData)
                .foregroundStyle(DS.DSColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(DS.DSColor.bgElevated)
        )
    }

    /// Progress bar against the user's daily goal. Caps the visual fill
    /// at 100% even if the user blew past the goal — the text label
    /// shows the actual ratio either way.
    private func goalProgressBar(todayMinutes: Double, goalMinutes: Double) -> some View {
        let fraction = min(1, todayMinutes / goalMinutes)
        let reached = todayMinutes >= goalMinutes
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text("DAILY GOAL")
                    .font(DS.Font.label)
                    .tracking(2)
                    .foregroundStyle(DS.DSColor.textMuted)
                Spacer()
                Text("\(Int(todayMinutes.rounded()))/\(Int(goalMinutes)) min")
                    .font(DS.Font.monoData)
                    .foregroundStyle(reached ? DS.DSColor.semanticOk : DS.DSColor.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(DS.DSColor.bgRecessed)
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(reached ? DS.DSColor.semanticOk : DS.DSColor.accentTempo)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(DS.DSColor.bgElevated)
        )
    }

    // MARK: - Per-song breakdown

    private var bySongSection: some View {
        let groups = sessions.bySong()
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("BY SONG")
                .font(DS.Font.label)
                .tracking(2)
                .foregroundStyle(DS.DSColor.textMuted)
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                    songRow(
                        title: group.title,
                        count: group.count,
                        total: group.totalDuration,
                        bpmMin: group.bpmMin,
                        bpmMax: group.bpmMax
                    )
                    if idx < groups.count - 1 {
                        Divider().background(DS.DSColor.textDim)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.DSColor.bgElevated)
            )
        }
    }

    private func songRow(title: String, count: Int, total: TimeInterval, bpmMin: BPM?, bpmMax: BPM?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .foregroundStyle(DS.DSColor.textPrimary)
                Text(subtitle(count: count, bpmMin: bpmMin, bpmMax: bpmMax))
                    .font(DS.Font.label)
                    .foregroundStyle(DS.DSColor.textMuted)
            }
            Spacer()
            Text(Self.formatDuration(total))
                .font(DS.Font.monoData)
                .foregroundStyle(DS.DSColor.textPrimary)
        }
        .padding(DS.Spacing.md)
    }

    /// "3 sessions · 80–120 BPM" / "1 session · 120 BPM" / "3 sessions"
    /// — collapses range to a single number when min == max, drops the
    /// BPM segment entirely when no data is available.
    private func subtitle(count: Int, bpmMin: BPM?, bpmMax: BPM?) -> String {
        let countStr = "\(count) session\(count == 1 ? "" : "s")"
        guard let lo = bpmMin, let hi = bpmMax else { return countStr }
        if lo == hi { return "\(countStr) · \(lo.displayInt) BPM" }
        return "\(countStr) · \(lo.displayInt)–\(hi.displayInt) BPM"
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            // ShareLink wraps the CSV string in a temporary file for the
            // share sheet so Mail/Files/Drive can save it natively.
            ShareLink(
                item: csvFileURL(),
                preview: SharePreview("Practice sessions", image: Image(systemName: "doc.text"))
            ) {
                Label("Export CSV", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(DS.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(DS.DSColor.bgElevated)
                    )
            }
            .foregroundStyle(DS.DSColor.accentTempo)

            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Text("Clear History")
                    .frame(maxWidth: .infinity)
                    .padding(DS.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(DS.DSColor.bgElevated)
                    )
            }
        }
    }

    /// Write the CSV to a temporary file so ShareLink can ship it as
    /// `practice-sessions.csv` instead of a blob of text. Same temp dir
    /// the share sheet picks up by default.
    private func csvFileURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("practice-sessions.csv")
        try? viewModel.practiceSessionsCSV().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Formatting

    /// Compact duration: "1h 24m" / "37m" / "0m" — drops zero hour
    /// components, always shows minutes for the at-a-glance read.
    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
