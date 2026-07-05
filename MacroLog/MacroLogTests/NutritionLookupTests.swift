import XCTest
@testable import MacroLog

final class NutritionLookupTests: XCTestCase {
    private func food(
        _ description: String,
        dataType: String = "SR Legacy",
        kcal: Double = 100,
        protein: Double = 10,
        carbs: Double = 20,
        fat: Double = 5
    ) -> USDAFood {
        USDAFood(
            fdcId: Int.random(in: 1...1_000_000),
            description: description,
            dataType: dataType,
            brandOwner: nil,
            foodNutrients: [
                .init(nutrientId: 1008, nutrientName: "Energy", unitName: "KCAL", value: kcal),
                .init(nutrientId: 1003, nutrientName: "Protein", unitName: "G", value: protein),
                .init(nutrientId: 1005, nutrientName: "Carbohydrate, by difference", unitName: "G", value: carbs),
                .init(nutrientId: 1004, nutrientName: "Total lipid (fat)", unitName: "G", value: fat),
            ]
        )
    }

    // MARK: Unit → grams conversion

    func testWeightUnitsConvertExactly() {
        let grams = USDANutritionLookupService.gramsFor(quantity: 2, unit: "oz")
        XCTAssertEqual(grams.value, 56.7, accuracy: 0.01)
        XCTAssertTrue(grams.isExact)

        let cup = USDANutritionLookupService.gramsFor(quantity: 1.5, unit: "cups")
        XCTAssertEqual(cup.value, 360, accuracy: 0.01)
        XCTAssertTrue(cup.isExact)
    }

    func testCountUnitsFallBackAndFlagInexact() {
        let grams = USDANutritionLookupService.gramsFor(quantity: 2, unit: "slice")
        XCTAssertEqual(grams.value, 200)
        XCTAssertFalse(grams.isExact)
    }

    // MARK: Best-match selection

    func testBestMatchPrefersOverlappingDescription() {
        let foods = [
            food("Cheese, cheddar"),
            food("Chicken breast, grilled"),
            food("Rice, white, cooked"),
        ]
        let best = USDANutritionLookupService.bestMatch(for: "grilled chicken breast", in: foods)
        XCTAssertEqual(best?.food.description, "Chicken breast, grilled")
        XCTAssertEqual(best?.score ?? 0, 1.0, accuracy: 0.001)
    }

    func testBestMatchPrefersGenericOverBrandedOnTies() {
        let foods = [
            food("Chicken breast", dataType: "Branded"),
            food("Chicken breast", dataType: "Foundation"),
        ]
        let best = USDANutritionLookupService.bestMatch(for: "chicken breast", in: foods)
        XCTAssertEqual(best?.food.dataType, "Foundation")
    }

    // MARK: Scaling & confidence

    func testMatchScalesMacrosToGrams() {
        // 200 g of a 100-kcal/10p/20c/5f per-100g food → doubled macros.
        let match = USDANutritionLookupService.match(
            for: FoodItemRequest(name: "white rice", quantity: 200, unit: "g"),
            food: food("Rice, white, cooked"),
            nameScore: 1.0
        )
        XCTAssertEqual(match.calories, 200, accuracy: 0.01)
        XCTAssertEqual(match.protein, 20, accuracy: 0.01)
        XCTAssertEqual(match.carbs, 40, accuracy: 0.01)
        XCTAssertEqual(match.fat, 10, accuracy: 0.01)
        XCTAssertEqual(match.confidence, MatchConfidence.high)
    }

    func testLowNameScoreFlagsLowConfidence() {
        let match = USDANutritionLookupService.match(
            for: FoodItemRequest(name: "dragonfruit smoothie", quantity: 100, unit: "g"),
            food: food("Cheese, cheddar"),
            nameScore: 0.1
        )
        XCTAssertEqual(match.confidence, MatchConfidence.low)
    }

    func testInexactUnitFlagsLowConfidence() {
        let match = USDANutritionLookupService.match(
            for: FoodItemRequest(name: "egg", quantity: 2, unit: "large"),
            food: food("Egg, whole, cooked"),
            nameScore: 1.0
        )
        XCTAssertEqual(match.confidence, MatchConfidence.low)
    }

    func testAtwaterEnergyFallback() {
        let foundation = USDAFood(
            fdcId: 1,
            description: "Almonds, raw",
            dataType: "Foundation",
            brandOwner: nil,
            foodNutrients: [
                .init(nutrientId: 2048, nutrientName: "Energy (Atwater Specific Factors)", unitName: "KCAL", value: 579),
                .init(nutrientId: 1003, nutrientName: "Protein", unitName: "G", value: 21),
            ]
        )
        XCTAssertEqual(foundation.macrosPer100g.calories, 579)
        XCTAssertEqual(foundation.macrosPer100g.protein, 21)
    }
}
