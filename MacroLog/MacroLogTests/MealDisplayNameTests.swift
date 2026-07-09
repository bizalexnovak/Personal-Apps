import XCTest
@testable import MacroLog

/// The meal lists show food names only, joined naturally — not the raw
/// transcript or a "Scanned label: …" prefix.
final class MealDisplayNameTests: XCTestCase {
    private func meal(_ names: [String], rawText: String) -> Meal {
        Meal(rawText: rawText, items: names.map { FoodItem(name: $0, quantity: 1, unit: "serving") })
    }

    func testSingleItemShowsJustTheName() {
        XCTAssertEqual(meal(["chicken"], rawText: "I ate chicken").displayName, "chicken")
    }

    func testTwoItemsJoinWithAnd() {
        XCTAssertEqual(
            meal(["chicken", "green beans"], rawText: "I ate chicken and green beans").displayName,
            "chicken and green beans"
        )
    }

    func testThreeItemsUseCommasAndAnd() {
        XCTAssertEqual(
            meal(["eggs", "toast", "bacon"], rawText: "eggs toast and bacon").displayName,
            "eggs, toast and bacon"
        )
    }

    func testScannedLabelShowsProductNameNotPrefix() {
        XCTAssertEqual(
            meal(["Celsius Sparkling Orange"], rawText: "Scanned label: Celsius Sparkling Orange").displayName,
            "Celsius Sparkling Orange"
        )
    }

    func testFallsBackToRawTextWhenNoItems() {
        XCTAssertEqual(meal([], rawText: "something").displayName, "something")
    }
}
