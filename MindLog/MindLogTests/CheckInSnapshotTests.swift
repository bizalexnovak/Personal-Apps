import XCTest
@testable import MindLog

/// Covers the pure logic in Shared/CheckInSharing.swift — the parts the
/// widget extension and the app both lean on. No SwiftData, no UserDefaults,
/// no `.now`: every date here is explicit so a run at any hour asserts the
/// same thing.
final class CheckInSnapshotTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - resolved(for:)

    func testResolvedPreservesSameDaySnapshot() {
        let day = date(2026, 8, 7, 9, 0)
        let snapshot = CheckInSnapshot(day: calendar.startOfDay(for: day), latestMood: 4, latestMoodAt: day, checkInCount: 2)
        let laterSameDay = date(2026, 8, 7, 22, 0)

        let resolved = snapshot.resolved(for: laterSameDay, calendar: calendar)

        XCTAssertEqual(resolved, snapshot)
    }

    func testResolvedBlanksAnEarlierDaySnapshot() {
        let yesterday = date(2026, 8, 6, 20, 0)
        let snapshot = CheckInSnapshot(day: calendar.startOfDay(for: yesterday), latestMood: 5, latestMoodAt: yesterday, checkInCount: 3)
        let today = date(2026, 8, 7, 8, 0)

        let resolved = snapshot.resolved(for: today, calendar: calendar)

        XCTAssertNil(resolved.latestMood)
        XCTAssertNil(resolved.latestMoodAt)
        XCTAssertEqual(resolved.checkInCount, 0)
        XCTAssertEqual(resolved.day, calendar.startOfDay(for: today))
    }

    // MARK: - adding(mood:at:)

    func testAddingIncrementsCountAndSetsLatestMood() {
        let firstTap = date(2026, 8, 7, 9, 0)
        let secondTap = date(2026, 8, 7, 15, 30)
        let empty = CheckInSnapshot(day: calendar.startOfDay(for: firstTap))

        let afterFirst = empty.adding(mood: 3, at: firstTap, calendar: calendar)
        XCTAssertEqual(afterFirst.latestMood, 3)
        XCTAssertEqual(afterFirst.latestMoodAt, firstTap)
        XCTAssertEqual(afterFirst.checkInCount, 1)

        let afterSecond = afterFirst.adding(mood: 5, at: secondTap, calendar: calendar)
        XCTAssertEqual(afterSecond.latestMood, 5)
        XCTAssertEqual(afterSecond.latestMoodAt, secondTap)
        XCTAssertEqual(afterSecond.checkInCount, 2)
    }

    func testAddingAcrossMidnightResetsCountInsteadOfAccumulating() {
        let yesterday = date(2026, 8, 6, 21, 0)
        let stale = CheckInSnapshot(day: calendar.startOfDay(for: yesterday), latestMood: 2, latestMoodAt: yesterday, checkInCount: 4)
        let todayTap = date(2026, 8, 7, 7, 45)

        let next = stale.adding(mood: 4, at: todayTap, calendar: calendar)

        XCTAssertEqual(next.checkInCount, 1)
        XCTAssertEqual(next.latestMood, 4)
        XCTAssertEqual(next.latestMoodAt, todayTap)
        XCTAssertEqual(next.day, calendar.startOfDay(for: todayTap))
    }

    // MARK: - CheckInInbox.trimmed(_:)

    func testTrimmedKeepsQueueUnderCapacityUnchanged() {
        let items = (0..<10).map { PendingCheckIn(moodScore: 3, timestamp: date(2026, 8, 7, 9, $0), origin: .widget) }
        XCTAssertEqual(CheckInInbox.trimmed(items), items)
    }

    func testTrimmedCapsAtCapacityKeepingTheNewest() {
        let items = (0..<(CheckInInbox.capacity + 10)).map { index in
            PendingCheckIn(moodScore: 3, timestamp: date(2026, 8, 7, 0) + Double(index), origin: .widget)
        }

        let trimmed = CheckInInbox.trimmed(items)

        XCTAssertEqual(trimmed.count, CheckInInbox.capacity)
        XCTAssertEqual(trimmed, Array(items.suffix(CheckInInbox.capacity)))
        // The oldest ten were the ones dropped.
        XCTAssertFalse(trimmed.contains(items[0]))
    }
}
