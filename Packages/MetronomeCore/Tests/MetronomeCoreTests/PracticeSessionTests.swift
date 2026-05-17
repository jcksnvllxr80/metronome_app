import Testing
import Foundation
@testable import MetronomeCore

// MARK: - Construction

@Test func durationIsPositive() {
    let now = Date()
    let session = PracticeSession(
        startedAt: now,
        endedAt: now.addingTimeInterval(300),
        bpmAtStart: BPM(120),
        bpmAtStop: BPM(120)
    )
    #expect(session.duration == 300)
}

@Test func invertedDatesClampToZeroDuration() {
    // Defend against a system-clock backward jump mid-session.
    let now = Date()
    let session = PracticeSession(
        startedAt: now,
        endedAt: now.addingTimeInterval(-100),
        bpmAtStart: BPM(120),
        bpmAtStop: BPM(120)
    )
    #expect(session.duration == 0)
}

// MARK: - Aggregations

@Test func totalDurationSumsAcrossSessions() {
    let now = Date()
    let sessions: [PracticeSession] = [
        PracticeSession(startedAt: now, endedAt: now.addingTimeInterval(120),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
        PracticeSession(startedAt: now, endedAt: now.addingTimeInterval(180),
                        bpmAtStart: BPM(100), bpmAtStop: BPM(100)),
    ]
    #expect(sessions.totalDuration == 300)
}

@Test func startedOnOrAfterFiltersCorrectly() {
    let now = Date()
    let cutoff = now.addingTimeInterval(-100)
    let sessions: [PracticeSession] = [
        // Before cutoff — should be excluded.
        PracticeSession(startedAt: now.addingTimeInterval(-200), endedAt: now.addingTimeInterval(-180),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
        // Exactly at cutoff — included.
        PracticeSession(startedAt: cutoff, endedAt: cutoff.addingTimeInterval(30),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
        // After cutoff — included.
        PracticeSession(startedAt: now, endedAt: now.addingTimeInterval(10),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
    ]
    let filtered = sessions.started(onOrAfter: cutoff)
    #expect(filtered.count == 2)
}

@Test func bySongAggregates() {
    let song1 = UUID()
    let song2 = UUID()
    let now = Date()
    let sessions: [PracticeSession] = [
        PracticeSession(startedAt: now, endedAt: now.addingTimeInterval(60),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120),
                        songID: song1, songTitle: "Wonderwall"),
        PracticeSession(startedAt: now, endedAt: now.addingTimeInterval(120),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120),
                        songID: song1, songTitle: "Wonderwall"),
        PracticeSession(startedAt: now, endedAt: now.addingTimeInterval(30),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120),
                        songID: song2, songTitle: "Smoke on the Water"),
        // Freestyle (no song) bucketed separately.
        PracticeSession(startedAt: now, endedAt: now.addingTimeInterval(45),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
    ]
    let groups = sessions.bySong()
    #expect(groups.count == 3)
    // Wonderwall has the most time (180s) so it's first.
    #expect(groups[0].title == "Wonderwall")
    #expect(groups[0].count == 2)
    #expect(groups[0].totalDuration == 180)
    // Freestyle takes 45s, between the two song entries.
    let freestyle = groups.first { $0.title == "Freestyle" }
    #expect(freestyle != nil)
    #expect(freestyle?.totalDuration == 45)
}

// MARK: - Codable

@Test func codableRoundTrip() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let session = PracticeSession(
        startedAt: now,
        endedAt: now.addingTimeInterval(600),
        bpmAtStart: BPM(80),
        bpmAtStop: BPM(120),
        songID: UUID(),
        songTitle: "Test Song",
        setlistID: UUID(),
        setlistName: "Friday Practice"
    )
    let data = try JSONEncoder().encode(session)
    let decoded = try JSONDecoder().decode(PracticeSession.self, from: data)
    #expect(decoded == session)
}

// MARK: - CSV export

@Test func csvHeaderAlwaysPresent() {
    let csv = ([] as [PracticeSession]).csv
    #expect(csv.starts(with: "id,started_at,ended_at,duration_seconds,bpm_at_start,bpm_at_stop,bpm_min,bpm_max,song_title,setlist_name\n"))
}

@Test func legacyConstructionDerivesMinMaxFromStartStop() {
    // Callers that pass only start/stop (e.g. a Codable decoder that
    // didn't see bpm_min/bpm_max keys) should get derived min/max.
    let now = Date()
    let session = PracticeSession(
        startedAt: now,
        endedAt: now.addingTimeInterval(60),
        bpmAtStart: BPM(80),
        bpmAtStop: BPM(120)
    )
    #expect(session.bpmMin == BPM(80))
    #expect(session.bpmMax == BPM(120))
}

@Test func dailyTotalsReturnsDenseSequence() {
    // 7-day window with no sessions → 7 entries, all zero.
    let totals = ([] as [PracticeSession]).dailyTotals(forLast: 7)
    #expect(totals.count == 7)
    #expect(totals.allSatisfy { $0.total == 0 })
}

@Test func dailyTotalsBucketsSessionsToCorrectDay() {
    // Two sessions on day 0 (today) + one on day -2 + one OUTSIDE the
    // window (day -10) — that last one should be dropped.
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
    let tenDaysAgo = cal.date(byAdding: .day, value: -10, to: today)!
    let sessions = [
        PracticeSession(startedAt: today, endedAt: today.addingTimeInterval(300),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
        PracticeSession(startedAt: today.addingTimeInterval(3600), endedAt: today.addingTimeInterval(3900),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
        PracticeSession(startedAt: twoDaysAgo, endedAt: twoDaysAgo.addingTimeInterval(600),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
        PracticeSession(startedAt: tenDaysAgo, endedAt: tenDaysAgo.addingTimeInterval(60),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
    ]
    let totals = sessions.dailyTotals(forLast: 7, ending: today, calendar: cal)
    #expect(totals.count == 7)
    // Newest entry (index 6 = today) should hold 300+300 = 600 seconds.
    #expect(totals.last?.total == 600)
    // Index 4 (= today - 2 days) should hold 600 seconds.
    #expect(totals[4].total == 600)
    // The day-10 session is outside the window, so total stays at 0
    // elsewhere.
    let nonZeroCount = totals.filter { $0.total > 0 }.count
    #expect(nonZeroCount == 2)
}

@Test func weeklyTotalsReturnsDenseSequence() {
    // 8-week window with no sessions → 8 entries, all zero.
    let totals = ([] as [PracticeSession]).weeklyTotals(forLast: 8)
    #expect(totals.count == 8)
    #expect(totals.allSatisfy { $0.total == 0 })
}

@Test func weeklyTotalsBucketsSessionsByWeek() {
    // Anchor in mid-week so sessions across day boundaries within the
    // same week aggregate correctly. Use a fixed Gregorian calendar so
    // the test is locale-independent.
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 1 // Sunday
    let today = cal.date(from: DateComponents(year: 2026, month: 5, day: 14))! // a Thursday
    let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
    let tenDaysAgo = cal.date(byAdding: .day, value: -10, to: today)!
    let outsideWindow = cal.date(byAdding: .weekOfYear, value: -8, to: today)!
    let sessions = [
        PracticeSession(startedAt: today, endedAt: today.addingTimeInterval(300),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
        PracticeSession(startedAt: yesterday, endedAt: yesterday.addingTimeInterval(600),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
        PracticeSession(startedAt: tenDaysAgo, endedAt: tenDaysAgo.addingTimeInterval(900),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
        PracticeSession(startedAt: outsideWindow, endedAt: outsideWindow.addingTimeInterval(60),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120)),
    ]
    let totals = sessions.weeklyTotals(forLast: 4, ending: today, calendar: cal)
    #expect(totals.count == 4)
    // The two same-week sessions (today + yesterday) aggregate to 900s
    // in the most-recent bucket.
    #expect(totals.last?.total == 900)
    // tenDaysAgo lands in an earlier week — should be a non-zero bucket.
    let nonZeroCount = totals.filter { $0.total > 0 }.count
    #expect(nonZeroCount == 2, "Two distinct weeks have practice")
    // Outside-window session dropped.
    let total = totals.reduce(0) { $0 + $1.total }
    #expect(total == 900 + 900, "Only sessions inside the 4-week window aggregate")
}

@Test func weeklyTotalsReturnedInChronologicalOrder() {
    let cal = Calendar(identifier: .gregorian)
    let totals = ([] as [PracticeSession]).weeklyTotals(forLast: 5, ending: Date(), calendar: cal)
    let dates = totals.map { $0.date }
    #expect(dates == dates.sorted(), "Buckets returned oldest → newest")
}

@Test func explicitMinMaxAreRespected() {
    let now = Date()
    let session = PracticeSession(
        startedAt: now,
        endedAt: now.addingTimeInterval(60),
        bpmAtStart: BPM(100),
        bpmAtStop: BPM(100),
        bpmMin: BPM(80),
        bpmMax: BPM(140)
    )
    #expect(session.bpmMin == BPM(80))
    #expect(session.bpmMax == BPM(140))
}

@Test func csvIncludesOneRowPerSession() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let sessions = [
        PracticeSession(startedAt: now, endedAt: now.addingTimeInterval(60),
                        bpmAtStart: BPM(120), bpmAtStop: BPM(120),
                        songTitle: "Song A"),
        PracticeSession(startedAt: now, endedAt: now.addingTimeInterval(120),
                        bpmAtStart: BPM(100), bpmAtStop: BPM(110)),
    ]
    let lines = sessions.csv.split(separator: "\n", omittingEmptySubsequences: false)
    // Header + 2 rows + trailing newline → 3 non-empty lines.
    #expect(lines.filter { !$0.isEmpty }.count == 3)
}

@Test func csvEscapesEmbeddedCommas() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let session = PracticeSession(
        startedAt: now, endedAt: now.addingTimeInterval(60),
        bpmAtStart: BPM(120), bpmAtStop: BPM(120),
        songTitle: "Song, with comma"
    )
    let csv = [session].csv
    #expect(csv.contains("\"Song, with comma\""))
}

@Test func csvEscapesEmbeddedQuotes() {
    let now = Date()
    let session = PracticeSession(
        startedAt: now, endedAt: now.addingTimeInterval(60),
        bpmAtStart: BPM(120), bpmAtStop: BPM(120),
        songTitle: "She said \"yes\""
    )
    let csv = [session].csv
    // Doubled quotes per RFC 4180.
    #expect(csv.contains("\"She said \"\"yes\"\"\""))
}
