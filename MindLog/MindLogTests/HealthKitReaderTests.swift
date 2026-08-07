import XCTest
@testable import MindLog

/// Covers only the pure helpers on `HealthKitReader` and `DayHealthSnapshot`
/// — no HealthKit, no device, no network.
final class HealthKitReaderTests: XCTestCase {
    // MARK: - sleepHours(fromAsleepSeconds:)

    func testSleepHoursNilForEmptyArray() {
        XCTAssertNil(HealthKitReader.sleepHours(fromAsleepSeconds: []))
    }

    func testSleepHoursSumsAndConvertsToHours() {
        // 3 hours + 1 hour = 4 hours, expressed as seconds.
        let hours = HealthKitReader.sleepHours(fromAsleepSeconds: [3 * 3600, 3600])
        XCTAssertEqual(hours, 4, accuracy: 0.0001)
    }

    // MARK: - hoursText

    func testHoursTextWithHoursAndMinutes() {
        XCTAssertEqual(HealthKitReader.hoursText(7 + 20.0 / 60.0), "7h 20m")
    }

    func testHoursTextUnderAnHour() {
        XCTAssertEqual(HealthKitReader.hoursText(45.0 / 60.0), "45m")
    }

    func testHoursTextWholeHours() {
        XCTAssertEqual(HealthKitReader.hoursText(8), "8h")
    }

    // MARK: - nightWindow

    func testNightWindowSpansPreviousEveningToNoon() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let components = DateComponents(year: 2026, month: 3, day: 10)
        let day = calendar.date(from: components)!

        let window = HealthKitReader.nightWindow(for: day, calendar: calendar)

        let expectedStart = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 9, hour: 18)
        )!
        let expectedEnd = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)
        )!

        XCTAssertEqual(window.start, expectedStart)
        XCTAssertEqual(window.end, expectedEnd)
    }

    // MARK: - DayHealthSnapshot.summary

    func testSummaryNilWhenBothMissing() {
        let snapshot = DayHealthSnapshot(day: .now, sleepHours: nil, steps: nil)
        XCTAssertNil(snapshot.summary)
    }

    func testSummaryIncludesOnlySleepWhenStepsMissing() {
        let snapshot = DayHealthSnapshot(day: .now, sleepHours: 7.5, steps: nil)
        XCTAssertEqual(snapshot.summary, "7h 30m sleep")
    }

    func testSummaryIncludesOnlyStepsWhenSleepMissing() {
        let snapshot = DayHealthSnapshot(day: .now, sleepHours: nil, steps: 6412)
        XCTAssertEqual(snapshot.summary, "6,412 steps")
    }

    func testSummaryCombinesBothWithThousandsSeparator() {
        let snapshot = DayHealthSnapshot(day: .now, sleepHours: 7 + 20.0 / 60.0, steps: 6412)
        XCTAssertEqual(snapshot.summary, "7h 20m sleep · 6,412 steps")
    }
}
