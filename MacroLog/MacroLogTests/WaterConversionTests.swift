import XCTest
@testable import MacroLog

final class WaterConversionTests: XCTestCase {
    func testDetectsWater() {
        XCTAssertTrue(WaterConversion.isWater("water"))
        XCTAssertTrue(WaterConversion.isWater("sparkling water"))
        XCTAssertTrue(WaterConversion.isWater("ice water"))
    }

    func testDoesNotMistakeWatermelonForWater() {
        XCTAssertFalse(WaterConversion.isWater("watermelon"))
        XCTAssertFalse(WaterConversion.isWater("chicken"))
    }

    func testVolumeUnitsConvertToOunces() {
        XCTAssertEqual(WaterConversion.ounces(quantity: 16, unit: "oz"), 16, accuracy: 0.001)
        XCTAssertEqual(WaterConversion.ounces(quantity: 1, unit: "bottle"), 16.9, accuracy: 0.001)
        XCTAssertEqual(WaterConversion.ounces(quantity: 2, unit: "glasses"), 16, accuracy: 0.001)
        XCTAssertEqual(WaterConversion.ounces(quantity: 1, unit: "cup"), 8, accuracy: 0.001)
        XCTAssertEqual(WaterConversion.ounces(quantity: 1, unit: "L"), 33.814, accuracy: 0.001)
        XCTAssertEqual(WaterConversion.ounces(quantity: 500, unit: "ml"), 16.907, accuracy: 0.01)
    }

    func testUnknownUnitFallsBackToAGlass() {
        XCTAssertEqual(WaterConversion.ounces(quantity: 1, unit: "swig"), 8, accuracy: 0.001)
    }

    func testOuncesForItemOnlyCountsWater() {
        let water = FoodItem(name: "water", quantity: 1, unit: "bottle")
        let chicken = FoodItem(name: "chicken", quantity: 6, unit: "oz")
        XCTAssertEqual(WaterConversion.ounces(for: water), 16.9, accuracy: 0.001)
        XCTAssertEqual(WaterConversion.ounces(for: chicken), 0, accuracy: 0.001)
    }

    func testMealWaterOuncesSumsWaterItemsOnly() {
        let meal = Meal(rawText: "chicken and two glasses of water", items: [
            FoodItem(name: "chicken", quantity: 6, unit: "oz", calories: 280),
            FoodItem(name: "water", quantity: 2, unit: "glasses"),
        ])
        XCTAssertEqual(meal.waterOunces, 16, accuracy: 0.001)
        XCTAssertEqual(meal.totalCalories, 280, accuracy: 0.001)
    }
}
