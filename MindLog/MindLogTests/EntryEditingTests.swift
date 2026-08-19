import XCTest
@testable import MindLog

/// Pure-logic coverage for `EntryEditing` and `CheckInSync`. No device, no
/// network, no ModelContext — everything under test here is a plain
/// function or a plain-init model, so a fixed calendar/clock is enough.
final class EntryEditingTests: XCTestCase {

    /// Gregorian, fixed to UTC, so `isDate(inSameDayAs:)` and day-math don't
    /// wobble with the host machine's time zone or DST.
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        return calendar.date(from: comps)!
    }

    // MARK: - EntryEditing.clamp

    func test_clamp_snapsFutureDateBackToNow() {
        let now = date(2026, 8, 7, 10, 0)
        let future = date(2026, 8, 8, 10, 0)
        XCTAssertEqual(EntryEditing.clamp(future, now: now, calendar: calendar), now)
    }

    func test_clamp_leavesValidPastDateAlone() {
        let now = date(2026, 8, 7, 10, 0)
        let recentPast = date(2026, 8, 1, 9, 30)
        XCTAssertEqual(EntryEditing.clamp(recentPast, now: now, calendar: calendar), recentPast)
    }

    func test_clamp_floorsDateOlderThanMaximumBackdateDays() {
        let now = date(2026, 8, 7, 10, 0)
        let tooFarBack = calendar.date(byAdding: .day, value: -400, to: now)!
        let earliest = EntryEditing.earliestAllowed(now: now, calendar: calendar)
        XCTAssertEqual(EntryEditing.clamp(tooFarBack, now: now, calendar: calendar), earliest)
    }

    // MARK: - EntryEditing.backdated(toDayOf:)

    func test_backdated_landsOnRequestedDayAndKeepsCurrentTimeOfDay() {
        let now = date(2026, 8, 7, 14, 45)
        let yesterday = date(2026, 8, 6, 0, 0)
        let backdated = EntryEditing.backdated(toDayOf: yesterday, now: now, calendar: calendar)

        XCTAssertTrue(calendar.isDate(backdated, inSameDayAs: yesterday))
        let comps = calendar.dateComponents([.hour, .minute], from: backdated)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 45)
    }

    // MARK: - EntryEditing.changesDay

    func test_changesDay_falseWithinSameDay() {
        let morning = date(2026, 8, 7, 8, 0)
        let evening = date(2026, 8, 7, 20, 0)
        XCTAssertFalse(EntryEditing.changesDay(from: morning, to: evening, calendar: calendar))
    }

    func test_changesDay_trueAcrossMidnight() {
        let lateNight = date(2026, 8, 7, 23, 59)
        let nextMorning = date(2026, 8, 8, 0, 1)
        XCTAssertTrue(EntryEditing.changesDay(from: lateNight, to: nextMorning, calendar: calendar))
    }

    // MARK: - CheckInSync.unsynced

    func test_unsynced_filtersOutIdsAlreadyPresent() {
        let existing = UUID()
        let newOne = UUID()
        let pending = [
            PendingCheckIn(id: existing, moodScore: 3, timestamp: .now, origin: .widget),
            PendingCheckIn(id: newOne, moodScore: 4, timestamp: .now, origin: .widget),
        ]
        let result = CheckInSync.unsynced(pending: pending, existingIDs: [existing])
        XCTAssertEqual(result.map(\.id), [newOne])
    }

    func test_unsynced_dedupesRepeatsWithinTheQueueAndPreservesOrder() {
        let a = UUID()
        let b = UUID()
        let pending = [
            PendingCheckIn(id: a, moodScore: 2, timestamp: .now, origin: .widget),
            PendingCheckIn(id: b, moodScore: 5, timestamp: .now, origin: .notification),
            PendingCheckIn(id: a, moodScore: 2, timestamp: .now, origin: .widget),
        ]
        let result = CheckInSync.unsynced(pending: pending, existingIDs: [])
        XCTAssertEqual(result.map(\.id), [a, b])
    }

    // MARK: - CheckInSync.snapshot

    func test_snapshot_picksLatestSameDayMood() {
        let day = date(2026, 8, 7, 12, 0)
        let entries = [
            JournalEntry(timestamp: date(2026, 8, 7, 8, 0), source: EntrySource.checkIn, moodScore: 2),
            JournalEntry(timestamp: date(2026, 8, 7, 18, 0), source: EntrySource.checkIn, moodScore: 5),
            JournalEntry(timestamp: date(2026, 8, 6, 22, 0), source: EntrySource.checkIn, moodScore: 1),
        ]
        let snapshot = CheckInSync.snapshot(from: entries, on: day, calendar: calendar)
        XCTAssertEqual(snapshot.latestMood, 5)
    }

    func test_snapshot_countsOnlySameDayRowsWithAMood() {
        let day = date(2026, 8, 7, 12, 0)
        let entries = [
            JournalEntry(timestamp: date(2026, 8, 7, 8, 0), source: EntrySource.checkIn, moodScore: 2),
            JournalEntry(timestamp: date(2026, 8, 7, 9, 0), text: "no mood today", source: EntrySource.typed),
            JournalEntry(timestamp: date(2026, 8, 6, 22, 0), source: EntrySource.checkIn, moodScore: 1),
        ]
        let snapshot = CheckInSync.snapshot(from: entries, on: day, calendar: calendar)
        XCTAssertEqual(snapshot.checkInCount, 1)
    }
}
