import XCTest
@testable import MindLog

final class InsightsEngineTests: XCTestCase {
    private let calendar = Calendar.current

    private func day(_ offset: Int, from reference: Date = .now) -> Date {
        calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: offset, to: reference) ?? reference
        )
    }

    private func summary(
        _ offset: Int, score: Double = 20, mood: Double? = nil,
        activities: Set<String> = [], journaled: Bool = false
    ) -> DaySummary {
        DaySummary(
            date: day(offset), score: score, averageMood: mood,
            activityIDs: activities, journaled: journaled
        )
    }

    // MARK: - Streaks

    func testStreakCountsBackFromToday() {
        let days = [summary(0), summary(-1), summary(-2)]
        XCTAssertEqual(InsightsEngine.currentStreak(days: days, today: .now), 3)
    }

    func testStreakSurvivesTodayNotYetLogged() {
        // Nothing today, but yesterday and before — the streak isn't broken
        // by a day still in progress.
        let days = [summary(-1), summary(-2)]
        XCTAssertEqual(InsightsEngine.currentStreak(days: days, today: .now), 2)
    }

    func testStreakBreaksOnAGap() {
        let days = [summary(0), summary(-2), summary(-3)]
        XCTAssertEqual(InsightsEngine.currentStreak(days: days, today: .now), 1)
    }

    func testZeroScoreDaysDoNotCount() {
        let days = [summary(0, score: 0), summary(-1)]
        XCTAssertEqual(InsightsEngine.currentStreak(days: days, today: .now), 1)
    }

    func testNoActivityMeansNoStreak() {
        XCTAssertEqual(InsightsEngine.currentStreak(days: [], today: .now), 0)
    }

    func testBestStreakFindsLongestRun() {
        // Two runs: 2 days and 4 days.
        let days = [
            summary(0), summary(-1),
            summary(-5), summary(-6), summary(-7), summary(-8),
        ]
        XCTAssertEqual(InsightsEngine.bestStreak(days: days), 4)
    }

    // MARK: - Mood lift

    func testMoodLiftComparesWithAndWithoutDays() {
        var days: [DaySummary] = []
        // 3 meditation days at mood 4, 3 plain days at mood 3.
        for i in 0..<3 {
            days.append(summary(-i, mood: 4, activities: [ActivityCatalog.meditation]))
        }
        for i in 3..<6 {
            days.append(summary(-i, mood: 3))
        }
        let lift = InsightsEngine.moodLift(activityID: ActivityCatalog.meditation, days: days)
        XCTAssertEqual(lift ?? 0, 1.0, accuracy: 0.001)
    }

    func testMoodLiftNeedsAMinimumSampleOnBothSides() {
        // Only two meditation days with mood — not enough to claim anything.
        let days = [
            summary(0, mood: 5, activities: [ActivityCatalog.meditation]),
            summary(-1, mood: 5, activities: [ActivityCatalog.meditation]),
            summary(-2, mood: 3),
            summary(-3, mood: 3),
            summary(-4, mood: 3),
        ]
        XCTAssertNil(InsightsEngine.moodLift(activityID: ActivityCatalog.meditation, days: days))
    }

    func testMoodLiftIgnoresDaysWithoutMood() {
        var days: [DaySummary] = []
        for i in 0..<3 {
            days.append(summary(-i, mood: 4, activities: [ActivityCatalog.exercise]))
        }
        for i in 3..<6 {
            days.append(summary(-i, mood: 2))
        }
        // Unrated days shouldn't shift the comparison.
        days.append(summary(-6, mood: nil, activities: [ActivityCatalog.exercise]))
        days.append(summary(-7, mood: nil))
        let lift = InsightsEngine.moodLift(activityID: ActivityCatalog.exercise, days: days)
        XCTAssertEqual(lift ?? 0, 2.0, accuracy: 0.001)
    }

    func testJournalingLiftUsesJournaledFlag() {
        var days: [DaySummary] = []
        for i in 0..<3 { days.append(summary(-i, mood: 4, journaled: true)) }
        for i in 3..<6 { days.append(summary(-i, mood: 3.5)) }
        XCTAssertEqual(InsightsEngine.journalingMoodLift(days: days) ?? 0, 0.5, accuracy: 0.001)
    }

    // MARK: - Weekly delta

    func testWeeklyMoodDeltaComparesTheTwoWeeks() {
        var days: [DaySummary] = []
        for i in 0..<7 { days.append(summary(-i, mood: 4)) }
        for i in 7..<14 { days.append(summary(-i, mood: 3)) }
        let delta = InsightsEngine.weeklyMoodDelta(days: days, today: .now)
        XCTAssertEqual(delta ?? 0, 1.0, accuracy: 0.001)
    }

    func testWeeklyMoodDeltaNilWithoutPriorWeek() {
        let days = [summary(0, mood: 4), summary(-1, mood: 4)]
        XCTAssertNil(InsightsEngine.weeklyMoodDelta(days: days, today: .now))
    }

    // MARK: - Cards

    func testInsightsIncludeStreakAndBestLift() {
        var days: [DaySummary] = []
        for i in 0..<4 {
            days.append(summary(-i, mood: 4.5, activities: [ActivityCatalog.meditation]))
        }
        for i in 4..<8 {
            days.append(summary(-i, mood: 3))
        }
        let cards = InsightsEngine.insights(days: days, today: .now)
        XCTAssertTrue(cards.contains { $0.id == "streak" })
        XCTAssertTrue(cards.contains { $0.id == "lift.\(ActivityCatalog.meditation)" })
    }

    func testNoInsightsFromThinData() {
        let days = [summary(0, mood: 3)]
        XCTAssertTrue(InsightsEngine.insights(days: days, today: .now).isEmpty)
    }
}

final class DayAggregatorTests: XCTestCase {
    private let calendar = Calendar.current

    func testSummariesGroupByCalendarDay() {
        let noon = calendar.date(
            bySettingHour: 12, minute: 0, second: 0, of: calendar.startOfDay(for: .now)
        ) ?? .now
        let evening = calendar.date(byAdding: .hour, value: 8, to: noon) ?? noon
        let yesterdayNoon = calendar.date(byAdding: .day, value: -1, to: noon) ?? noon

        let entries = [
            JournalEntry(timestamp: noon, text: "Solid morning.", moodScore: 4),
            JournalEntry(timestamp: evening, source: EntrySource.checkIn, moodScore: 2),
            JournalEntry(timestamp: yesterdayNoon, text: "Yesterday's note."),
        ]
        let logs = [
            ActivityLog(timestamp: noon, activityID: ActivityCatalog.meditation, minutes: 10),
        ]

        let summaries = DayAggregator.summaries(entries: entries, logs: logs)
        XCTAssertEqual(summaries.count, 2)

        let today = summaries.last
        XCTAssertEqual(today?.averageMood ?? 0, 3.0, accuracy: 0.001) // (4 + 2) / 2
        XCTAssertEqual(today?.activityIDs, [ActivityCatalog.meditation])
        XCTAssertTrue(today?.journaled ?? false)
        // 10 min meditation (12) + journal (15) + check-in (5).
        XCTAssertEqual(today?.score ?? 0, 32, accuracy: 0.001)

        let yesterday = summaries.first
        XCTAssertNil(yesterday?.averageMood)
        XCTAssertTrue(yesterday?.journaled ?? false)
    }

    func testSummariesAreSortedByDate() {
        let today = calendar.startOfDay(for: .now)
        let entries = [
            JournalEntry(timestamp: calendar.date(byAdding: .day, value: -3, to: today) ?? today, text: "a"),
            JournalEntry(timestamp: today, text: "b"),
            JournalEntry(timestamp: calendar.date(byAdding: .day, value: -1, to: today) ?? today, text: "c"),
        ]
        let summaries = DayAggregator.summaries(entries: entries, logs: [])
        XCTAssertEqual(summaries.map(\.date), summaries.map(\.date).sorted())
    }
}
