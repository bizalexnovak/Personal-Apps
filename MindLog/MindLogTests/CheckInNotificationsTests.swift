import XCTest
@testable import MindLog

/// A deterministic generator so `fireTimes` output is reproducible across
/// runs — a simple linear congruential generator seeded once per test.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class CheckInNotificationsTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testDisabledReturnsEmpty() {
        var window = CheckInWindow()
        window.isEnabled = false
        var generator = SeededGenerator(seed: 1)
        let times = CheckInNotifications.fireTimes(
            window: window, daysAhead: 3, from: date(2026, 8, 7, 8), calendar: calendar, using: &generator
        )
        XCTAssertTrue(times.isEmpty)
    }

    func testInvalidWindowReturnsEmpty() {
        var window = CheckInWindow()
        window.isEnabled = true
        window.startHour = 21
        window.endHour = 10
        var generator = SeededGenerator(seed: 1)
        let times = CheckInNotifications.fireTimes(
            window: window, daysAhead: 3, from: date(2026, 8, 7, 8), calendar: calendar, using: &generator
        )
        XCTAssertTrue(times.isEmpty)
    }

    func testCountMatchesPerDayTimesDaysAheadWhenFullyInFuture() {
        var window = CheckInWindow()
        window.isEnabled = true
        window.startHour = 10
        window.endHour = 21
        window.perDay = 3
        // "now" is before the window starts on day 0, so nothing is dropped.
        let now = date(2026, 8, 7, 0, 0)
        var generator = SeededGenerator(seed: 42)
        let times = CheckInNotifications.fireTimes(
            window: window, daysAhead: 4, from: now, calendar: calendar, using: &generator
        )
        XCTAssertEqual(times.count, window.perDay * 4)
    }

    func testEveryTimeFallsInsideWindow() {
        var window = CheckInWindow()
        window.isEnabled = true
        window.startHour = 9
        window.endHour = 17
        window.perDay = 4
        let now = date(2026, 8, 7, 0, 0)
        var generator = SeededGenerator(seed: 7)
        let times = CheckInNotifications.fireTimes(
            window: window, daysAhead: 5, from: now, calendar: calendar, using: &generator
        )
        for time in times {
            let hour = calendar.component(.hour, from: time)
            XCTAssertGreaterThanOrEqual(hour, window.startHour)
            XCTAssertLessThan(hour, window.endHour)
        }
    }

    func testTimesAreSortedAndStrictlyIncreasing() {
        var window = CheckInWindow()
        window.isEnabled = true
        window.startHour = 8
        window.endHour = 20
        window.perDay = 3
        let now = date(2026, 8, 7, 0, 0)
        var generator = SeededGenerator(seed: 99)
        let times = CheckInNotifications.fireTimes(
            window: window, daysAhead: 3, from: now, calendar: calendar, using: &generator
        )
        XCTAssertEqual(times, times.sorted())
        for i in 1..<times.count {
            XCTAssertLessThan(times[i - 1], times[i])
        }
    }

    func testPastTimesOnFirstDayAreDropped() {
        var window = CheckInWindow()
        window.isEnabled = true
        window.startHour = 9
        window.endHour = 17
        window.perDay = 2
        // "now" is at the very end of the window on day 0, so day 0's times
        // are almost certainly already in the past.
        let now = date(2026, 8, 7, 16, 59)
        var generator = SeededGenerator(seed: 5)
        let times = CheckInNotifications.fireTimes(
            window: window, daysAhead: 2, from: now, calendar: calendar, using: &generator
        )
        for time in times {
            XCTAssertGreaterThan(time, now)
        }
        // Day 1's two fires always survive; day 0 may contribute at most one
        // more (its second sub-window straddles `now`), never both.
        XCTAssertGreaterThanOrEqual(times.count, window.perDay)
        XCTAssertLessThanOrEqual(times.count, window.perDay + 1)
    }

    func testDeterministicForSeededGenerator() {
        var window = CheckInWindow()
        window.isEnabled = true
        window.startHour = 10
        window.endHour = 21
        window.perDay = 2
        let now = date(2026, 8, 7, 0, 0)

        var generatorA = SeededGenerator(seed: 123)
        let timesA = CheckInNotifications.fireTimes(
            window: window, daysAhead: 3, from: now, calendar: calendar, using: &generatorA
        )

        var generatorB = SeededGenerator(seed: 123)
        let timesB = CheckInNotifications.fireTimes(
            window: window, daysAhead: 3, from: now, calendar: calendar, using: &generatorB
        )

        XCTAssertEqual(timesA, timesB)
    }
}
