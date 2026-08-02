import XCTest
@testable import Foob

final class MealSuggestionsTests: XCTestCase {
    /// A one-item meal logged at a given clock hour, `daysAgo` days back.
    private func meal(_ name: String, hour: Int, daysAgo: Int, kcal: Double = 100) -> Meal {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: .now))!
        let date = cal.date(byAdding: .hour, value: hour, to: day)!
        return Meal(
            timestamp: date,
            rawText: name,
            items: [FoodItem(name: name, quantity: 1, unit: "serving", calories: kcal)]
        )
    }

    private func time(hour: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: hour, to: Calendar.current.startOfDay(for: .now))!
    }

    func testSingleLogsAreNotSuggested() {
        let suggestions = MealSuggestions.compute(from: [meal("eggs", hour: 8, daysAgo: 1)])
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testTimeOfDayOutranksRawFrequency() {
        // Eggs: 2 logs at 8 AM. Yogurt: 3 logs at 8 PM. At breakfast time the
        // eggs (score 2 + 2×2 = 6) beat the more-frequent yogurt (score 3).
        let meals = [
            meal("eggs", hour: 8, daysAgo: 1),
            meal("eggs", hour: 8, daysAgo: 2),
            meal("yogurt", hour: 20, daysAgo: 1),
            meal("yogurt", hour: 20, daysAgo: 2),
            meal("yogurt", hour: 20, daysAgo: 3),
        ]
        let morning = MealSuggestions.compute(from: meals, now: time(hour: 8))
        XCTAssertEqual(morning.first?.name, "eggs")
        XCTAssertEqual(morning.count, 2, "both repeats still appear, just reordered")

        let evening = MealSuggestions.compute(from: meals, now: time(hour: 20))
        XCTAssertEqual(evening.first?.name, "yogurt")
    }

    func testFrequencyStillBreaksTiesAwayFromNow() {
        // Neither logged near 2 PM — plain frequency decides.
        let meals = [
            meal("eggs", hour: 8, daysAgo: 1),
            meal("eggs", hour: 8, daysAgo: 2),
            meal("yogurt", hour: 20, daysAgo: 1),
            meal("yogurt", hour: 20, daysAgo: 2),
            meal("yogurt", hour: 20, daysAgo: 3),
        ]
        let afternoon = MealSuggestions.compute(from: meals, now: time(hour: 14))
        XCTAssertEqual(afternoon.first?.name, "yogurt")
    }

    func testCircularHourDistanceWrapsMidnight() {
        XCTAssertEqual(MealSuggestions.circularHourDistance(23, 1), 2)
        XCTAssertEqual(MealSuggestions.circularHourDistance(0, 23), 1)
        XCTAssertEqual(MealSuggestions.circularHourDistance(12, 12), 0)
        XCTAssertEqual(MealSuggestions.circularHourDistance(6, 18), 12)
    }
}
