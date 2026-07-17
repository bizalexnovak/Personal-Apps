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

    func testCaffeinatedWaterIsNotPlainWater() {
        // Caffeinated waters carry a real caffeine content, so they go
        // through USDA (which has it) instead of the plain-water shortcut.
        XCTAssertFalse(WaterConversion.isWater("caffeine water"))
        XCTAssertFalse(WaterConversion.isWater("caffeinated water"))
    }

    func testVolumeUnitsConvertToOunces() {
        XCTAssertEqual(WaterConversion.ounces(quantity: 24, unit: "ounces"), 24, accuracy: 0.001)
        XCTAssertEqual(WaterConversion.ounces(quantity: 1, unit: "bottle"), 16, accuracy: 0.001)
        XCTAssertEqual(WaterConversion.ounces(quantity: 1, unit: "glass"), 8, accuracy: 0.001)
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
        XCTAssertEqual(WaterConversion.ounces(for: water), 16, accuracy: 0.001)
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

final class SupplementConversionTests: XCTestCase {
    func testBareCreatineMatches() {
        let match = SupplementConversion.match(
            for: FoodItemRequest(name: "creatine", quantity: 5, unit: "grams")
        )
        XCTAssertEqual(match?.calories, 0)
        XCTAssertEqual(match?.micros.creatine ?? 0, 5, accuracy: 0.001)
    }

    func testCreatineMonohydrateScoopMatches() {
        let match = SupplementConversion.match(
            for: FoodItemRequest(name: "creatine monohydrate", quantity: 1, unit: "scoop")
        )
        XCTAssertEqual(match?.micros.creatine ?? 0, 5, accuracy: 0.001)
    }

    func testCaffeinePillMatchesAtDefaultDose() {
        let match = SupplementConversion.match(
            for: FoodItemRequest(name: "caffeine pill", quantity: 1, unit: "pill")
        )
        XCTAssertEqual(match?.calories, 0)
        XCTAssertEqual(match?.micros.caffeine ?? 0, 200, accuracy: 0.001)
    }

    func testCaloricProductsDoNotMatch() {
        // Real foods that merely mention the supplement must keep their
        // calories — they go through the normal lookup instead.
        XCTAssertNil(SupplementConversion.match(
            for: FoodItemRequest(name: "creatine gummies", quantity: 3, unit: "pieces")
        ))
        XCTAssertNil(SupplementConversion.match(
            for: FoodItemRequest(name: "high caffeine energy drink", quantity: 1, unit: "can")
        ))
        XCTAssertNil(SupplementConversion.match(
            for: FoodItemRequest(name: "caffeine free coke", quantity: 1, unit: "can")
        ))
    }

    func testZeroDoseDoesNotMatch() {
        XCTAssertNil(SupplementConversion.match(
            for: FoodItemRequest(name: "creatine", quantity: 0, unit: "grams")
        ))
    }

    func testBrandedSupplementNamesGoToLookupByDesign() {
        // Brand words are unbounded, so branded/flavored phrasings fall
        // through to the USDA lookup (which carries real data) instead of
        // dose-guessing — documented trade-off, not an accident.
        XCTAssertNil(SupplementConversion.match(
            for: FoodItemRequest(name: "Optimum Nutrition creatine monohydrate", quantity: 1, unit: "scoop")
        ))
        XCTAssertNil(SupplementConversion.match(
            for: FoodItemRequest(name: "caffeine gum", quantity: 1, unit: "piece")
        ))
    }

    func testDoseUnitConversions() {
        XCTAssertEqual(SupplementConversion.creatineGrams(quantity: 5000, unit: "mg"), 5, accuracy: 0.001)
        XCTAssertEqual(SupplementConversion.caffeineMilligrams(quantity: 100, unit: "mg"), 100, accuracy: 0.001)
        XCTAssertEqual(SupplementConversion.caffeineMilligrams(quantity: 2, unit: "pills"), 400, accuracy: 0.001)
    }
}
