import XCTest
@testable import Foob

final class NutritionLookupTests: XCTestCase {
    // MARK: - Fixture helpers

    private func food(
        _ description: String,
        dataType: String = "SR Legacy",
        brandOwner: String? = nil,
        servingSize: Double? = nil,
        servingSizeUnit: String? = nil,
        householdServing: String? = nil,
        kcal: Double = 100,
        protein: Double = 10,
        carbs: Double = 12,
        fat: Double = 1.3
    ) -> USDAFood {
        USDAFood(
            fdcId: abs(description.hashValue % 1_000_000),
            description: description,
            dataType: dataType,
            brandOwner: brandOwner,
            brandName: nil,
            servingSize: servingSize,
            servingSizeUnit: servingSizeUnit,
            householdServingFullText: householdServing,
            foodNutrients: [
                .init(nutrientId: 1008, nutrientName: "Energy", unitName: "KCAL", value: kcal),
                .init(nutrientId: 1003, nutrientName: "Protein", unitName: "G", value: protein),
                .init(nutrientId: 1005, nutrientName: "Carbohydrate, by difference", unitName: "G", value: carbs),
                .init(nutrientId: 1004, nutrientName: "Total lipid (fat)", unitName: "G", value: fat),
            ]
        )
    }

    // Realistic USDA-style fixtures for the four regression cases.

    private var brandedTurkeyBacon: USDAFood {
        food(
            "OSCAR MAYER TURKEY BACON", dataType: "Branded", brandOwner: "Oscar Mayer",
            servingSize: 15, servingSizeUnit: "g", householdServing: "1 SLICE",
            kcal: 217, protein: 17.2, carbs: 2.2, fat: 15.5
        )
    }

    private var srTurkeyBacon: USDAFood {
        food("Turkey bacon, microwaved", kcal: 368, protein: 29.5, carbs: 3.1, fat: 25.9)
    }

    private var brandedChobani: USDAFood {
        food(
            "CHOBANI NON-FAT GREEK YOGURT PLAIN", dataType: "Branded", brandOwner: "Chobani, LLC",
            servingSize: 170, servingSizeUnit: "g", householdServing: "1 CONTAINER",
            kcal: 57, protein: 10.2, carbs: 4.1, fat: 0.2
        )
    }

    private var srGreekYogurt: USDAFood {
        food("Yogurt, Greek, plain, nonfat", kcal: 59, protein: 10.2, carbs: 3.6, fat: 0.4)
    }

    private var brandedEggs: USDAFood {
        food(
            "GRADE A LARGE EGGS", dataType: "Branded", brandOwner: "Kroger",
            servingSize: 50, servingSizeUnit: "g", householdServing: "1 EGG",
            kcal: 143, protein: 12.6, carbs: 0.7, fat: 9.5
        )
    }

    private var srRawEgg: USDAFood {
        food("Egg, whole, raw, fresh", kcal: 143, protein: 12.6, carbs: 0.7, fat: 9.5)
    }

    private var surveyCookedRice: USDAFood {
        food(
            "Rice, white, cooked, regular, no added fat", dataType: "Survey (FNDDS)",
            kcal: 130, protein: 2.7, carbs: 28.2, fat: 0.28
        )
    }

    private var brandedDryRice: USDAFood {
        food(
            "MAHATMA ENRICHED EXTRA LONG GRAIN WHITE RICE", dataType: "Branded",
            brandOwner: "Riviana Foods",
            servingSize: 45, servingSizeUnit: "g", householdServing: "1/4 cup",
            kcal: 356, protein: 6.7, carbs: 80, fat: 0
        )
    }

    private var srCookedRice: USDAFood {
        food("Rice, white, long-grain, regular, cooked", kcal: 130, protein: 2.7, carbs: 28.2, fat: 0.28)
    }

    private let cookedRicePortions = [
        USDAPortion(amount: 1, gramWeight: 158, modifier: nil, portionDescription: "1 cup, cooked", measureUnit: nil)
    ]

    // MARK: - Regression case 1: "one piece of turkey bacon"

    func testTurkeyBaconPieceUsesBrandedSliceWeight() {
        let request = FoodItemRequest(name: "turkey bacon", quantity: 1, unit: "piece")
        let foods = [srTurkeyBacon, brandedTurkeyBacon]

        let selection = USDANutritionLookupService.selectCandidate(for: request, in: foods)
        XCTAssertEqual(selection?.food.description, "OSCAR MAYER TURKEY BACON")

        let result = USDANutritionLookupService.evaluate(
            for: request, food: selection!.food, nameScore: selection!.score
        )
        // 1 slice = 15 g → 15% of the per-100g values.
        XCTAssertEqual(result.match.calories, 32.55, accuracy: 0.1)
        XCTAssertEqual(result.match.protein, 2.58, accuracy: 0.01)
        XCTAssertEqual(result.match.confidence, MatchConfidence.high)
        XCTAssertTrue(result.flags.isEmpty)
    }

    func testTurkeyBaconOldBehaviorIsNowFlagged() {
        // The reported bug: SR entry scaled at an assumed 100 g/piece → 368 kcal.
        // If that path is ever hit again it must come out low-confidence.
        let request = FoodItemRequest(name: "turkey bacon", quantity: 1, unit: "piece")
        let result = USDANutritionLookupService.evaluate(
            for: request, food: srTurkeyBacon, nameScore: 1.0
        )
        XCTAssertEqual(result.match.calories, 368, accuracy: 0.1)
        XCTAssertEqual(result.match.confidence, MatchConfidence.low)
        XCTAssertFalse(result.flags.isEmpty, "368 kcal for one piece must trip the sanity bound")
    }

    // MARK: - Regression case 2: "a Chobani greek yogurt"

    func testChobaniYogurtUsesBrandServingSize() {
        let request = FoodItemRequest(name: "Chobani greek yogurt", quantity: 1, unit: "container")
        let foods = [srGreekYogurt, brandedChobani]

        let selection = USDANutritionLookupService.selectCandidate(for: request, in: foods)
        XCTAssertEqual(selection?.food.description, "CHOBANI NON-FAT GREEK YOGURT PLAIN")
        XCTAssertTrue(USDANutritionLookupService.brandMentioned(query: request.name, food: brandedChobani))

        let result = USDANutritionLookupService.evaluate(
            for: request, food: selection!.food, nameScore: selection!.score
        )
        // 1 container = 170 g → 1.7 × per-100g values.
        XCTAssertEqual(result.match.calories, 96.9, accuracy: 0.1)
        XCTAssertEqual(result.match.protein, 17.34, accuracy: 0.01)
        XCTAssertEqual(result.match.confidence, MatchConfidence.high)
    }

    // MARK: - Regression case 3: "two eggs"

    func testTwoEggsUseDiscreteEggServing() {
        let request = FoodItemRequest(name: "eggs", quantity: 2, unit: "large")
        let foods = [srRawEgg, brandedEggs]

        let selection = USDANutritionLookupService.selectCandidate(for: request, in: foods)
        XCTAssertEqual(selection?.food.description, "GRADE A LARGE EGGS")

        let result = USDANutritionLookupService.evaluate(
            for: request, food: selection!.food, nameScore: selection!.score
        )
        // "1 EGG" = 50 g → 2 eggs = 100 g, not the old 2 × 100 g = 286 kcal.
        XCTAssertEqual(result.match.calories, 143, accuracy: 0.1)
        XCTAssertEqual(result.match.protein, 12.6, accuracy: 0.01)
        XCTAssertEqual(result.match.confidence, MatchConfidence.high)
    }

    // MARK: - Regression case 4: "a cup of rice"

    func testCupOfRicePrefersSurveyCookedOverBrandedDry() {
        let request = FoodItemRequest(name: "rice", quantity: 1, unit: "cup")
        let foods = [brandedDryRice, surveyCookedRice, srCookedRice]

        let selection = USDANutritionLookupService.selectCandidate(for: request, in: foods)
        XCTAssertEqual(selection?.food.dataType, "Survey (FNDDS)",
                       "volume request must not match dry packaged rice")

        let result = USDANutritionLookupService.evaluate(
            for: request, food: selection!.food, nameScore: selection!.score,
            portions: cookedRicePortions
        )
        // USDA portion "1 cup, cooked" = 158 g → 205 kcal, not 240 g water-density.
        XCTAssertEqual(result.match.calories, 205.4, accuracy: 0.5)
        XCTAssertEqual(result.match.carbs, 44.56, accuracy: 0.1)
        XCTAssertEqual(result.match.confidence, MatchConfidence.high)
    }

    // MARK: - Plausibility checks

    func testAtwaterMismatchIsFlagged() {
        let flags = USDANutritionLookupService.plausibilityFlags(
            calories: 500, protein: 10, carbs: 10, fat: 10, // expected ≈ 170
            grams: 200, quantity: 1, unitKind: .weight(gramsPerUnit: 200)
        )
        XCTAssertTrue(flags.contains { $0.contains("inconsistent") })
    }

    func testImpossibleEnergyDensityIsFlagged() {
        let flags = USDANutritionLookupService.plausibilityFlags(
            calories: 950, protein: 10, carbs: 10, fat: 100,
            grams: 100, quantity: 1, unitKind: .weight(gramsPerUnit: 100)
        )
        XCTAssertTrue(flags.contains { $0.contains("energy density") })
    }

    func testMacroMassExceedingWeightIsFlagged() {
        let flags = USDANutritionLookupService.plausibilityFlags(
            calories: 400, protein: 50, carbs: 50, fat: 10,
            grams: 100, quantity: 1, unitKind: .weight(gramsPerUnit: 100)
        )
        XCTAssertTrue(flags.contains { $0.contains("exceed") })
    }

    func testDiscreteBoundUsesUnitCategoryNotFood() {
        // 250 kcal is fine for a "large" item but not for a "slice".
        let sliceFlags = USDANutritionLookupService.plausibilityFlags(
            calories: 250, protein: 15, carbs: 2, fat: 21,
            grams: 0, quantity: 1, unitKind: .discrete(word: "slice")
        )
        XCTAssertTrue(sliceFlags.contains { $0.contains("sanity bound") })

        let largeFlags = USDANutritionLookupService.plausibilityFlags(
            calories: 250, protein: 15, carbs: 2, fat: 21,
            grams: 0, quantity: 1, unitKind: .discrete(word: "large")
        )
        XCTAssertFalse(largeFlags.contains { $0.contains("sanity bound") })
    }

    func testPlausibleMatchHasNoFlags() {
        let flags = USDANutritionLookupService.plausibilityFlags(
            calories: 143, protein: 12.6, carbs: 0.7, fat: 9.5,
            grams: 100, quantity: 2, unitKind: .discrete(word: "large")
        )
        XCTAssertTrue(flags.isEmpty)
    }

    // MARK: - Query ladder (branded multi-word searches)

    func testQueryLadderIsBrandFirst() {
        // Brand-specific rungs come before the generic category term.
        XCTAssertEqual(
            USDANutritionLookupService.queryLadder(for: "Celsius energy drink"),
            ["Celsius energy drink", "Celsius drink", "Celsius", "energy drink", "drink"]
        )
        XCTAssertEqual(
            USDANutritionLookupService.queryLadder(for: "Chobani mixed berry greek yogurt"),
            ["Chobani mixed berry greek yogurt", "Chobani yogurt", "Chobani", "greek yogurt", "yogurt"]
        )
        XCTAssertEqual(
            USDANutritionLookupService.queryLadder(for: "Goldfish crackers"),
            ["Goldfish crackers", "Goldfish", "crackers"]
        )
    }

    func testCelsiusIsTriedBeforeGenericEnergyDrink() {
        // "Celsius" must appear earlier in the ladder than "energy drink" so a
        // brand match is exhausted before the generic term can win.
        let ladder = USDANutritionLookupService.queryLadder(for: "Celsius energy drink")
        let celsiusIndex = try? XCTUnwrap(ladder.firstIndex(of: "Celsius"))
        let genericIndex = try? XCTUnwrap(ladder.firstIndex(of: "energy drink"))
        XCTAssertNotNil(celsiusIndex)
        XCTAssertNotNil(genericIndex)
        if let c = celsiusIndex, let g = genericIndex {
            XCTAssertLessThan(c, g)
        }
    }

    func testBrandInDescriptionOutranksGenericCandidate() {
        // If a single query returns both a real Celsius entry (~3 kcal/100ml)
        // and a generic energy drink (~43 kcal/100ml, Branded), the one whose
        // description contains "Celsius" must win.
        let celsius = food(
            "CELSIUS SPARKLING ORANGE ENERGY DRINK", dataType: "Branded",
            brandOwner: "Celsius Inc.",
            servingSize: 355, servingSizeUnit: "ml", householdServing: "1 can",
            kcal: 2.8, protein: 0, carbs: 0.6, fat: 0
        )
        let genericBrandedDrink = food(
            "MONSTER ENERGY DRINK", dataType: "Branded",
            brandOwner: "Monster Energy Co.",
            servingSize: 355, servingSizeUnit: "ml", householdServing: "1 can",
            kcal: 47, protein: 0, carbs: 12, fat: 0
        )
        let request = FoodItemRequest(name: "Celsius energy drink", quantity: 1, unit: "can")

        let selection = USDANutritionLookupService.selectCandidate(for: request, in: [genericBrandedDrink, celsius])
        XCTAssertEqual(selection?.food.description, "CELSIUS SPARKLING ORANGE ENERGY DRINK")

        let result = USDANutritionLookupService.evaluate(for: request, food: selection!.food, nameScore: selection!.score)
        XCTAssertEqual(result.match.calories, 9.94, accuracy: 0.1, "355 ml can × 2.8 kcal/100ml ≈ 10 kcal")
    }

    func testQueryLadderSingleWordHasNoFallbacks() {
        XCTAssertEqual(USDANutritionLookupService.queryLadder(for: "banana"), ["banana"])
    }

    // MARK: - Celsius product-line ranking

    func testCelsiusSelectionPrefersProductLineNamedInQuery() {
        // Two same-brand candidates: the actual energy drink (~3 kcal/100 ml)
        // and a caloric product line the brand also sells. The query names
        // "energy drink", so the drink must win on name score.
        let correct = food(
            "CELSIUS LIVE FIT SPARKLING ORANGE ENERGY DRINK", dataType: "Branded",
            brandOwner: "Celsius Inc.",
            servingSize: 355, servingSizeUnit: "ml", householdServing: "1 can",
            kcal: 2.8, protein: 0, carbs: 0.6, fat: 0
        )
        let decoy = food(
            "CELSIUS PROTEIN SHAKE, MIXED BERRY", dataType: "Branded",
            brandOwner: "Celsius Inc.",
            servingSize: 355, servingSizeUnit: "ml", householdServing: "1 bottle",
            kcal: 43, protein: 8.5, carbs: 1.5, fat: 0.5
        )
        let request = FoodItemRequest(name: "Celsius energy drink", quantity: 1, unit: "can")

        let selection = USDANutritionLookupService.selectCandidate(for: request, in: [decoy, correct])
        XCTAssertEqual(selection?.food.description, correct.description,
                       "a 43 kcal/100ml decoy (≈153 kcal/can) must not outrank the product line the user named")

        let result = USDANutritionLookupService.evaluate(
            for: request, food: selection!.food, nameScore: selection!.score
        )
        XCTAssertEqual(result.match.calories, 9.94, accuracy: 0.1)
    }

    // MARK: - Low-calorie legitimacy (values are never zeroed or rejected)

    func testLegitimatelyNearZeroCalorieDrinkKeepsValuesAndHighConfidence() {
        // Celsius-style: ~3 kcal per 100 ml, 355 ml can.
        let celsius = food(
            "CELSIUS LIVE FIT SPARKLING ENERGY DRINK", dataType: "Branded",
            brandOwner: "Celsius Inc.",
            servingSize: 355, servingSizeUnit: "ml", householdServing: "1 can",
            kcal: 2.8, protein: 0, carbs: 0.6, fat: 0
        )
        let request = FoodItemRequest(name: "Celsius energy drink", quantity: 1, unit: "can")
        let result = USDANutritionLookupService.evaluate(for: request, food: celsius, nameScore: 1.0)

        XCTAssertEqual(result.match.calories, 9.94, accuracy: 0.1, "low calories are legitimate, not a failure")
        XCTAssertTrue(result.flags.isEmpty, "near-zero calories must not trip Atwater on tiny values")
        XCTAssertEqual(result.match.confidence, MatchConfidence.high)
    }

    func testImplausibleMatchKeepsItsValuesAndFlagsLow() {
        // Same scenario as the turkey-bacon regression: the values survive —
        // flagged low for review, never zeroed or rejected.
        let request = FoodItemRequest(name: "turkey bacon", quantity: 1, unit: "piece")
        let result = USDANutritionLookupService.evaluate(for: request, food: srTurkeyBacon, nameScore: 1.0)
        XCTAssertGreaterThan(result.match.calories, 0, "plausibility flags must never zero out a match")
        XCTAssertEqual(result.match.confidence, MatchConfidence.low)
    }

    // MARK: - Unit classification & serving parsing

    func testUnitClassification() {
        XCTAssertEqual(USDANutritionLookupService.classifyUnit("oz"), .weight(gramsPerUnit: 28.35))
        XCTAssertEqual(USDANutritionLookupService.classifyUnit("cups"), .volume(gramsPerUnit: 240))
        XCTAssertEqual(USDANutritionLookupService.classifyUnit("Slices"), .discrete(word: "slice"))
        XCTAssertEqual(USDANutritionLookupService.classifyUnit("containers"), .serving)
        XCTAssertEqual(USDANutritionLookupService.classifyUnit("smidgen"), .unknown)
    }

    func testVagueUnitsClassifyAsVague() {
        for word in ["bag", "bags", "bowl", "handful", "some", "bit"] {
            if case .vague = USDANutritionLookupService.classifyUnit(word) {
                continue
            }
            XCTFail("'\(word)' should classify as vague")
        }
    }

    func testVagueUnitNeverResolvesReliably() {
        let request = FoodItemRequest(name: "popcorn", quantity: 1, unit: "bag")
        let grams = USDANutritionLookupService.resolveGrams(
            for: request,
            food: food("Snacks, popcorn, oil-popped", kcal: 500, protein: 9, carbs: 57, fat: 28)
        )
        XCTAssertFalse(grams.isReliable)
        XCTAssertLessThanOrEqual(grams.grams, 100, "unclarified 'bag' must use a conservative single-portion guess")
    }

    func testUnclarifiedVagueUnitIsAlwaysFlagged() {
        // Even values that pass every numeric check get flagged when the
        // vague amount was never clarified.
        let flags = USDANutritionLookupService.plausibilityFlags(
            calories: 250, protein: 4.5, carbs: 28.5, fat: 14,
            grams: 50, quantity: 1, unitKind: .vague(word: "bag")
        )
        XCTAssertTrue(flags.contains { $0.contains("never clarified") })
    }

    func testVagueBulkAmountIsFlagged() {
        // A family-size match (700 kcal for "a bag") must trip the bound.
        let flags = USDANutritionLookupService.plausibilityFlags(
            calories: 700, protein: 12.6, carbs: 79.8, fat: 39.2,
            grams: 140, quantity: 1, unitKind: .vague(word: "bag")
        )
        XCTAssertTrue(flags.contains { $0.contains("bulk") })
    }

    func testHouseholdTextParsing() {
        let two = USDANutritionLookupService.parseHouseholdText("2 SLICES")
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two.descriptor, "slice")

        let quarter = USDANutritionLookupService.parseHouseholdText("1/4 cup")
        XCTAssertEqual(quarter.count, 0.25, accuracy: 0.001)
        XCTAssertEqual(quarter.descriptor, "cup")

        let container = USDANutritionLookupService.parseHouseholdText("1 container")
        XCTAssertEqual(container.count, 1)
        XCTAssertEqual(container.descriptor, "container")
    }

    func testServingInfoPerHouseholdUnit() {
        let bacon = food(
            "TURKEY BACON", dataType: "Branded",
            servingSize: 30, servingSizeUnit: "GRM", householdServing: "2 slices",
            kcal: 217, protein: 17.2, carbs: 2.2, fat: 15.5
        )
        let info = USDANutritionLookupService.servingInfo(for: bacon)
        XCTAssertEqual(info?.gramsPerHouseholdUnit ?? 0, 15, accuracy: 0.001)
    }

    // MARK: - Misc carried over

    func testAtwaterEnergyFallback() {
        let foundation = USDAFood(
            fdcId: 1,
            description: "Almonds, raw",
            dataType: "Foundation",
            brandOwner: nil,
            brandName: nil,
            servingSize: nil,
            servingSizeUnit: nil,
            householdServingFullText: nil,
            foodNutrients: [
                .init(nutrientId: 2048, nutrientName: "Energy (Atwater Specific Factors)", unitName: "KCAL", value: 579),
                .init(nutrientId: 1003, nutrientName: "Protein", unitName: "G", value: 21),
            ]
        )
        XCTAssertEqual(foundation.macrosPer100g.calories, 579)
        XCTAssertEqual(foundation.macrosPer100g.protein, 21)
    }
}
