import XCTest
@testable import MindLog

final class PracticeScoreTests: XCTestCase {
    func testEmptyDayScoresZero() {
        XCTAssertEqual(PracticeScore.score(for: .init()), 0, accuracy: 0.001)
    }

    func testActivityPointsUsePerMinuteRates() {
        // 10 min of meditation at 1.2 pts/min.
        let input = PracticeScore.DayInput(activityMinutes: [ActivityCatalog.meditation: 10])
        XCTAssertEqual(PracticeScore.score(for: input), 12, accuracy: 0.001)
    }

    func testDailyCapLimitsASingleActivity() {
        // Meditation caps at 30 counted minutes — three hours can't farm it.
        let input = PracticeScore.DayInput(activityMinutes: [ActivityCatalog.meditation: 180])
        XCTAssertEqual(PracticeScore.score(for: input), 36, accuracy: 0.001)
    }

    func testCapAppliesAcrossMultipleLogsOfSameActivity() {
        // Two 20-minute sessions share the same 30-minute cap.
        var input = PracticeScore.DayInput()
        input.activityMinutes[ActivityCatalog.meditation] = 40
        XCTAssertEqual(PracticeScore.score(for: input), 36, accuracy: 0.001)
    }

    func testVarietyOutscoresGrinding() {
        let grind = PracticeScore.DayInput(activityMinutes: [ActivityCatalog.meditation: 240])
        let varied = PracticeScore.DayInput(activityMinutes: [
            ActivityCatalog.meditation: 20,
            ActivityCatalog.outdoors: 30,
            ActivityCatalog.gratitude: 5,
        ])
        XCTAssertGreaterThan(
            PracticeScore.score(for: varied),
            PracticeScore.score(for: grind)
        )
    }

    func testJournalAndCheckInBonuses() {
        var input = PracticeScore.DayInput()
        input.journaled = true
        input.checkedIn = true
        XCTAssertEqual(
            PracticeScore.score(for: input),
            PracticeScore.journalBonus + PracticeScore.checkInBonus,
            accuracy: 0.001
        )
    }

    func testScoreIsCappedAtOneHundred() {
        var input = PracticeScore.DayInput()
        for activity in ActivityCatalog.all {
            input.activityMinutes[activity.id] = activity.capMinutes
        }
        input.journaled = true
        input.checkedIn = true
        XCTAssertEqual(PracticeScore.score(for: input), 100, accuracy: 0.001)
    }

    func testNegativeMinutesAreIgnored() {
        let input = PracticeScore.DayInput(activityMinutes: [ActivityCatalog.meditation: -20])
        XCTAssertEqual(PracticeScore.score(for: input), 0, accuracy: 0.001)
    }

    func testUnknownActivityStillEarnsFallbackPoints() {
        // A log from a future catalog version keeps earning via the fallback
        // activity instead of disappearing from the score.
        let input = PracticeScore.DayInput(activityMinutes: ["future_activity": 10])
        XCTAssertGreaterThan(PracticeScore.score(for: input), 0)
    }

    func testDayInputAggregation() {
        let entries = [
            JournalEntry(text: "Long day, but the walk helped.", source: EntrySource.voice),
            JournalEntry(source: EntrySource.checkIn, moodScore: 4),
        ]
        let logs = [
            ActivityLog(activityID: ActivityCatalog.meditation, minutes: 15),
            ActivityLog(activityID: ActivityCatalog.meditation, minutes: 10),
            ActivityLog(activityID: ActivityCatalog.outdoors, minutes: 30),
        ]
        let input = PracticeScore.dayInput(entries: entries, logs: logs)
        XCTAssertTrue(input.journaled)
        XCTAssertTrue(input.checkedIn)
        XCTAssertEqual(input.activityMinutes[ActivityCatalog.meditation] ?? 0, 25, accuracy: 0.001)
        XCTAssertEqual(input.activityMinutes[ActivityCatalog.outdoors] ?? 0, 30, accuracy: 0.001)
    }

    func testCheckInAloneIsNotJournaling() {
        let entries = [JournalEntry(source: EntrySource.checkIn, moodScore: 3)]
        let input = PracticeScore.dayInput(entries: entries, logs: [])
        XCTAssertFalse(input.journaled)
        XCTAssertTrue(input.checkedIn)
    }

    func testMoodDoesNotChangeTheScore() {
        // The score measures actions, not outcomes — a rough-mood day with the
        // same practices scores identically to a great-mood day.
        let entriesRough = [JournalEntry(text: "Awful day.", moodScore: 1)]
        let entriesGreat = [JournalEntry(text: "Wonderful day.", moodScore: 5)]
        let logs = [ActivityLog(activityID: ActivityCatalog.meditation, minutes: 10)]
        let rough = PracticeScore.score(for: PracticeScore.dayInput(entries: entriesRough, logs: logs))
        let great = PracticeScore.score(for: PracticeScore.dayInput(entries: entriesGreat, logs: logs))
        XCTAssertEqual(rough, great, accuracy: 0.001)
    }
}

final class ActivityCatalogTests: XCTestCase {
    func testCatalogIDsAreUnique() {
        let ids = ActivityCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testLookupReturnsCatalogEntries() {
        XCTAssertEqual(ActivityCatalog.activity(for: ActivityCatalog.meditation).name, "Meditation")
        XCTAssertTrue(ActivityCatalog.isKnown(ActivityCatalog.breathwork))
    }

    func testUnknownIDFallsBackGracefully() {
        let unknown = ActivityCatalog.activity(for: "not_a_real_activity")
        XCTAssertFalse(ActivityCatalog.isKnown("not_a_real_activity"))
        XCTAssertEqual(unknown.id, "not_a_real_activity")
        XCTAssertGreaterThan(unknown.pointsPerMinute, 0)
    }

    func testEveryActivityHasPresetsAndSaneNumbers() {
        for activity in ActivityCatalog.all {
            XCTAssertFalse(activity.presetMinutes.isEmpty, activity.id)
            XCTAssertGreaterThan(activity.pointsPerMinute, 0, activity.id)
            XCTAssertGreaterThan(activity.capMinutes, 0, activity.id)
            XCTAssertFalse(activity.icon.isEmpty, activity.id)
        }
    }

    func testNoSingleActivityCanMaxTheDayAlone() {
        for activity in ActivityCatalog.all {
            XCTAssertLessThan(
                activity.maxDailyPoints, PracticeScore.maxScore,
                "\(activity.id) alone should not reach the 100-point cap"
            )
        }
    }
}
