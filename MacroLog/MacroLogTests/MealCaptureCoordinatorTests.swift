import XCTest
import SwiftData
@testable import MacroLog

/// Exercises the parse → lookup → Match Review → Save All flow with parser
/// fixtures shaped like Claude's responses.
@MainActor
final class MealCaptureCoordinatorTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(AppModelContainer.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeCoordinator(
        parsed: [FoodItemRequest],
        matches: [String: NutritionMatch] = [:]
    ) -> MealCaptureCoordinator {
        let coordinator = MealCaptureCoordinator()
        coordinator.parser = MockMealParser(result: parsed)
        coordinator.logger = MealLoggingService(
            parser: MockMealParser(result: parsed),
            nutrition: MockNutritionLookup(matches: matches)
        )
        return coordinator
    }

    private func savedMeals(in context: ModelContext) throws -> [Meal] {
        try context.fetch(FetchDescriptor<Meal>())
    }

    private func match(
        _ description: String,
        kcal: Double,
        protein: Double = 0,
        confidence: String = MatchConfidence.high
    ) -> NutritionMatch {
        NutritionMatch(
            matchedDescription: description,
            calories: kcal, protein: protein, carbs: 0, fat: 0,
            confidence: confidence
        )
    }

    // MARK: - Fixtures

    private var clearEggs: FoodItemRequest {
        FoodItemRequest(name: "eggs", quantity: 2, unit: "large")
    }

    private var celsiusDrink: FoodItemRequest {
        FoodItemRequest(name: "Celsius energy drink", quantity: 1, unit: "can")
    }

    private var unflaggedSomeRice: FoodItemRequest {
        FoodItemRequest(name: "rice", quantity: 1, unit: "some")
    }

    private var flaggedChobani: FoodItemRequest {
        FoodItemRequest(
            name: "Chobani yogurt", quantity: 1, unit: "container",
            needsClarification: true,
            clarificationQuestion: "Which Chobani product was it?",
            options: [
                ClarificationOption(label: "Plain non-fat Greek (5.3 oz)", name: "Chobani non-fat plain greek yogurt", quantity: 1, unit: "container"),
                ClarificationOption(label: "Chobani Flip (4.5 oz)", name: "Chobani Flip greek yogurt", quantity: 1, unit: "container"),
            ]
        )
    }

    private var celsiusUSDAFood: USDAFood {
        USDAFood(
            fdcId: 12345,
            description: "CELSIUS LIVE FIT SPARKLING ORANGE ENERGY DRINK",
            dataType: "Branded",
            brandOwner: "Celsius Inc.",
            brandName: nil,
            servingSize: 355,
            servingSizeUnit: "ml",
            householdServingFullText: "1 can",
            foodNutrients: [
                .init(nutrientId: 1008, nutrientName: "Energy", unitName: "KCAL", value: 2.8),
                .init(nutrientId: 1003, nutrientName: "Protein", unitName: "G", value: 0),
                .init(nutrientId: 1005, nutrientName: "Carbohydrate, by difference", unitName: "G", value: 0.6),
                .init(nutrientId: 1004, nutrientName: "Total lipid (fat)", unitName: "G", value: 0),
            ]
        )
    }

    // MARK: - Session construction

    func testBeginBuildsReviewSessionWithoutSaving() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [clearEggs],
            matches: ["eggs": match("GRADE A LARGE EGGS", kcal: 143, protein: 12.6)]
        )

        await coordinator.begin(text: "two eggs", in: context)

        let review = try XCTUnwrap(coordinator.review)
        XCTAssertEqual(review.rawText, "two eggs")
        XCTAssertEqual(review.items.count, 1)
        XCTAssertEqual(review.items[0].status, .needsReview)
        XCTAssertEqual(review.items[0].match?.calories ?? 0, 143, accuracy: 0.01)
        XCTAssertFalse(coordinator.canSaveAll, "unreviewed items must block Save All")
        XCTAssertTrue(try savedMeals(in: context).isEmpty, "nothing saves before Save All")
    }

    func testConfirmThenSaveAllWritesMeal() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [clearEggs],
            matches: ["eggs": match("GRADE A LARGE EGGS", kcal: 143, protein: 12.6)]
        )

        await coordinator.begin(text: "two eggs", in: context)
        let itemID = try XCTUnwrap(coordinator.review?.items.first?.id)

        coordinator.confirm(itemID)
        XCTAssertTrue(coordinator.canSaveAll)

        await coordinator.saveAll()

        XCTAssertNil(coordinator.review, "review dismisses after saving")
        let meals = try savedMeals(in: context)
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals.first?.rawText, "two eggs")
        XCTAssertEqual(meals.first?.items.first?.calories ?? 0, 143, accuracy: 0.01)
    }

    // MARK: - Unmatched items

    func testUnmatchedItemCannotBeConfirmedAndBlocksSave() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [celsiusDrink]) // no matches → lookup fails

        await coordinator.begin(text: "one Celsius energy drink", in: context)

        let item = try XCTUnwrap(coordinator.review?.items.first)
        XCTAssertNil(item.match)
        XCTAssertTrue(item.needsAttention)

        coordinator.confirm(item.id) // must be a no-op with no match
        XCTAssertEqual(coordinator.review?.items.first?.status, .needsReview)
        XCTAssertFalse(coordinator.canSaveAll, "an unmatched item must never save (no silent zeros)")
    }

    func testApplyEditResolvesUnmatchedItemWithEnteredValues() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [celsiusDrink])

        await coordinator.begin(text: "one Celsius energy drink", in: context)
        let itemID = try XCTUnwrap(coordinator.review?.items.first?.id)

        coordinator.applyEdit(itemID, calories: 10, protein: 0, carbs: 2, fat: 0)

        XCTAssertEqual(coordinator.review?.items.first?.status, .edited)
        XCTAssertTrue(coordinator.canSaveAll)

        await coordinator.saveAll()
        let item = try XCTUnwrap(try savedMeals(in: context).first?.items.first)
        XCTAssertEqual(item.calories, 10, accuracy: 0.01, "the entered value is saved, never zero")
        XCTAssertEqual(item.matchConfidence, MatchConfidence.high)
    }

    func testApplyPickedFoodComputesMacrosAndConfirms() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [celsiusDrink])

        await coordinator.begin(text: "one Celsius energy drink", in: context)
        let itemID = try XCTUnwrap(coordinator.review?.items.first?.id)

        coordinator.applyPickedFood(itemID, food: celsiusUSDAFood)

        let item = try XCTUnwrap(coordinator.review?.items.first)
        XCTAssertEqual(item.status, .confirmed)
        // 2.8 kcal/100ml × 355 ml can ≈ 9.94 kcal
        XCTAssertEqual(item.match?.calories ?? 0, 9.94, accuracy: 0.1)
        XCTAssertTrue(coordinator.canSaveAll)
    }

    // MARK: - Clarification chips

    func testClaudeFlaggedItemCarriesOptionsOnCard() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [flaggedChobani],
            matches: ["Chobani yogurt": match("CHOBANI GREEK YOGURT", kcal: 97, confidence: MatchConfidence.low)]
        )

        await coordinator.begin(text: "a Chobani yogurt", in: context)

        let item = try XCTUnwrap(coordinator.review?.items.first)
        XCTAssertEqual(item.clarificationQuestion, "Which Chobani product was it?")
        XCTAssertEqual(item.options.count, 2)
    }

    func testVagueUnitGetsLocalFallbackOptions() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [unflaggedSomeRice],
            matches: ["rice": match("Rice, white, cooked", kcal: 130, confidence: MatchConfidence.low)]
        )

        await coordinator.begin(text: "some rice", in: context)

        let item = try XCTUnwrap(coordinator.review?.items.first)
        XCTAssertEqual(item.options.count, 3, "vague units get local size options even when the parser didn't flag them")
        XCTAssertTrue(item.options.allSatisfy { $0.unit == "g" })
    }

    func testChooseOptionSwapsRequestAndRelooksUp() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [unflaggedSomeRice],
            matches: ["rice": match("Rice, white, cooked", kcal: 130)]
        )

        await coordinator.begin(text: "some rice", in: context)
        let item = try XCTUnwrap(coordinator.review?.items.first)
        let medium = item.options[1] // "Medium portion (about 100 g)"

        await coordinator.chooseOption(item.id, option: medium)

        let updated = try XCTUnwrap(coordinator.review?.items.first)
        XCTAssertEqual(updated.request.unit, "g")
        XCTAssertEqual(updated.request.quantity, 100)
        XCTAssertTrue(updated.options.isEmpty, "chips clear once an interpretation is chosen")
        XCTAssertEqual(updated.status, .needsReview, "new macros still need a confirm tap")
    }

    // MARK: - Remove / cancel

    func testRemoveUnmatchedItemUnblocksSave() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [clearEggs, celsiusDrink],
            matches: ["eggs": match("GRADE A LARGE EGGS", kcal: 143)] // Celsius finds nothing
        )

        await coordinator.begin(text: "two eggs and a Celsius", in: context)
        let eggsID = try XCTUnwrap(coordinator.review?.items.first { $0.request.name == "eggs" }?.id)
        let celsiusID = try XCTUnwrap(coordinator.review?.items.first { $0.request.name.contains("Celsius") }?.id)

        coordinator.confirm(eggsID)
        XCTAssertFalse(coordinator.canSaveAll, "the unmatched item still blocks")

        coordinator.removeItem(celsiusID)
        XCTAssertTrue(coordinator.canSaveAll)

        await coordinator.saveAll()
        let meals = try savedMeals(in: context)
        XCTAssertEqual(meals.first?.items.count, 1)
        XCTAssertEqual(meals.first?.items.first?.name, "eggs")
    }

    func testRemovingEveryItemDisablesSave() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [celsiusDrink])

        await coordinator.begin(text: "a Celsius", in: context)
        let itemID = try XCTUnwrap(coordinator.review?.items.first?.id)

        coordinator.removeItem(itemID)

        XCTAssertFalse(coordinator.canSaveAll)
        await coordinator.saveAll() // must be a no-op
        XCTAssertTrue(try savedMeals(in: context).isEmpty)
    }

    func testCancelReviewDiscardsEverything() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [clearEggs],
            matches: ["eggs": match("GRADE A LARGE EGGS", kcal: 143)]
        )

        await coordinator.begin(text: "two eggs", in: context)
        XCTAssertNotNil(coordinator.review)

        coordinator.cancelReview()

        XCTAssertNil(coordinator.review)
        XCTAssertFalse(coordinator.isCapturing)
        XCTAssertTrue(try savedMeals(in: context).isEmpty)
    }

    func testLocalFallbackOptionsScaleWithQuantity() {
        let item = FoodItemRequest(name: "chips", quantity: 2, unit: "bag")
        let options = MealCaptureCoordinator.fallbackOptions(for: item, vagueWord: "bag")
        XCTAssertEqual(options.first?.quantity, 56, "2 bags × 28 g snack bag")
    }

    func testWaterItemSkipsLookupAndTalliesOunces() async throws {
        let context = try makeContext()
        // Empty nutrition matches — water must not need USDA at all.
        let coordinator = makeCoordinator(parsed: [FoodItemRequest(name: "water", quantity: 1, unit: "bottle")])

        await coordinator.begin(text: "a bottle of water", in: context)
        let item = try XCTUnwrap(coordinator.review?.items.first)
        XCTAssertNotNil(item.match, "water gets a 0-calorie match without a USDA lookup")
        XCTAssertEqual(item.match?.calories, 0)

        coordinator.confirm(item.id)
        XCTAssertTrue(coordinator.canSaveAll)
        await coordinator.saveAll()

        let meal = try XCTUnwrap(try savedMeals(in: context).first)
        XCTAssertEqual(meal.waterOunces, 16, accuracy: 0.01)
        XCTAssertEqual(meal.totalCalories, 0, accuracy: 0.001)
    }

    func testSpokenMacrosOverrideUsdaLookup() async throws {
        let context = try makeContext()
        // Even though a USDA match is available, the spoken numbers win.
        let request = FoodItemRequest(
            name: "chicken", quantity: 1, unit: "serving",
            calories: nil, protein: 64, carbs: 60, fat: 25
        )
        let coordinator = makeCoordinator(
            parsed: [request],
            matches: ["chicken": match("Chicken, cooked", kcal: 999)]
        )

        await coordinator.begin(text: "chicken, 64g protein, 60g carbs, 25g fat", in: context)
        let item = try XCTUnwrap(coordinator.review?.items.first)
        XCTAssertEqual(item.match?.protein, 64)
        XCTAssertEqual(item.match?.carbs, 60)
        XCTAssertEqual(item.match?.fat, 25)
        // Calories derived from macros: 64*4 + 60*4 + 25*9 = 721.
        XCTAssertEqual(item.match?.calories ?? 0, 721, accuracy: 0.5)
        XCTAssertNotEqual(item.match?.calories, 999, "spoken numbers must override the USDA match")
    }

    func testBareSupplementSkipsLookupAndRecordsDose() async throws {
        let context = try makeContext()
        // Empty nutrition matches — a bare supplement must not need USDA.
        let coordinator = makeCoordinator(parsed: [FoodItemRequest(name: "creatine", quantity: 5, unit: "grams")])

        await coordinator.begin(text: "5 grams of creatine", in: context)
        let item = try XCTUnwrap(coordinator.review?.items.first)
        XCTAssertEqual(item.match?.calories, 0)
        XCTAssertEqual(item.match?.micros.creatine ?? 0, 5, accuracy: 0.001)
    }

    func testExplicitMacrosBeatSupplementShortcut() async throws {
        let context = try makeContext()
        // A supplement-named item with user-stated macros keeps the stated
        // numbers — the supplement shortcut must not zero them.
        let request = FoodItemRequest(
            name: "creatine", quantity: 1, unit: "serving",
            calories: 40, protein: 0, carbs: 10, fat: 0
        )
        let coordinator = makeCoordinator(parsed: [request])

        await coordinator.begin(text: "creatine, 40 calories, 10 grams of carbs", in: context)
        let item = try XCTUnwrap(coordinator.review?.items.first)
        XCTAssertEqual(item.match?.calories, 40)
        XCTAssertEqual(item.match?.carbs, 10)
    }

    func testCaloricSupplementNamedFoodGoesToLookup() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [FoodItemRequest(name: "creatine gummies", quantity: 3, unit: "pieces")],
            matches: ["creatine gummies": match("Creatine gummies", kcal: 45)]
        )

        await coordinator.begin(text: "three creatine gummies", in: context)
        let item = try XCTUnwrap(coordinator.review?.items.first)
        XCTAssertEqual(item.match?.calories, 45, "real caloric products keep their looked-up calories")
    }

    func testWaterEditSetsOunces() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [FoodItemRequest(name: "water", quantity: 1, unit: "glass")])

        await coordinator.begin(text: "a glass of water", in: context)
        let itemID = try XCTUnwrap(coordinator.review?.items.first?.id)

        coordinator.applyWaterEdit(itemID, ounces: 24)
        await coordinator.saveAll()

        let meal = try XCTUnwrap(try savedMeals(in: context).first)
        XCTAssertEqual(meal.waterOunces, 24, accuracy: 0.01)
    }

    func testSetScaleIsAbsoluteAgainstBaseline() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [FoodItemRequest(name: "protein shake", quantity: 1, unit: "serving")],
            matches: ["protein shake": match("Protein shake", kcal: 160, protein: 30)]
        )
        await coordinator.begin(text: "protein shake", in: context)
        let id = try XCTUnwrap(coordinator.review?.items.first?.id)

        coordinator.setScale(id, factor: 2)
        let item = try XCTUnwrap(coordinator.review?.items.first)
        XCTAssertEqual(item.request.quantity, 2, accuracy: 0.001)
        XCTAssertEqual(item.match?.calories ?? 0, 320, accuracy: 0.001)
        XCTAssertEqual(item.match?.protein ?? 0, 60, accuracy: 0.001)

        // Absolute, not cumulative: 0.5× is half the baseline, not half of 2×.
        coordinator.setScale(id, factor: 0.5)
        XCTAssertEqual(coordinator.review?.items.first?.request.quantity ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(coordinator.review?.items.first?.match?.calories ?? 0, 80, accuracy: 0.001)

        // Back to 1× restores the original values exactly.
        coordinator.setScale(id, factor: 1)
        XCTAssertEqual(coordinator.review?.items.first?.match?.calories ?? 0, 160, accuracy: 0.001)
    }

    func testUSDAMicronutrientExtractionAndScaling() {
        let food = USDAFood(
            fdcId: 1, description: "Test food", dataType: "Branded",
            brandOwner: nil, brandName: nil, servingSize: 100, servingSizeUnit: "g",
            householdServingFullText: nil,
            foodNutrients: [
                .init(nutrientId: 1258, nutrientName: "Saturated fat", unitName: "G", value: 5),
                .init(nutrientId: 1093, nutrientName: "Sodium", unitName: "MG", value: 200),
                .init(nutrientId: 1079, nutrientName: "Fiber", unitName: "G", value: 3),
            ]
        )
        let per100 = food.micronutrientsPer100g
        XCTAssertEqual(per100.saturatedFat ?? 0, 5, accuracy: 0.001)
        XCTAssertEqual(per100.sodium ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(per100.fiber ?? 0, 3, accuracy: 0.001)
        XCTAssertNil(per100.cholesterol) // unrecorded stays nil, not 0

        let half = per100.scaled(by: 0.5)
        XCTAssertEqual(half.saturatedFat ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(half.fiber ?? 0, 1.5, accuracy: 0.001)
        XCTAssertNil(half.cholesterol)
    }

    func testMicronutrientsPersistAndScaleThroughSave() async throws {
        let context = try makeContext()
        let micros = Micronutrients(saturatedFat: 3, fiber: 2, sodium: 400)
        let barMatch = NutritionMatch(
            matchedDescription: "Protein bar", calories: 200, protein: 20,
            carbs: 24, fat: 8, confidence: MatchConfidence.high, micros: micros
        )
        let coordinator = makeCoordinator(
            parsed: [FoodItemRequest(name: "protein bar", quantity: 1, unit: "bar")],
            matches: ["protein bar": barMatch]
        )
        await coordinator.begin(text: "a protein bar", in: context)
        let id = try XCTUnwrap(coordinator.review?.items.first?.id)

        // Double the portion before saving — micros scale with the macros.
        coordinator.setScale(id, factor: 2)
        coordinator.confirm(id)
        await coordinator.saveAll()

        let meal = try XCTUnwrap(try savedMeals(in: context).first)
        let item = try XCTUnwrap(meal.items.first)
        XCTAssertEqual(item.micros.saturatedFat ?? 0, 6, accuracy: 0.001)
        XCTAssertEqual(item.micros.fiber ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(item.micros.sodium ?? 0, 800, accuracy: 0.001)
        XCTAssertNil(item.micros.transFat)
    }

    func testRenameUpdatesItemName() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [FoodItemRequest(name: "chicken", quantity: 1, unit: "serving")],
            matches: ["chicken": match("Chicken", kcal: 200)]
        )
        await coordinator.begin(text: "chicken", in: context)
        let id = try XCTUnwrap(coordinator.review?.items.first?.id)

        coordinator.rename(id, to: "chicken thigh")
        XCTAssertEqual(coordinator.review?.items.first?.request.name, "chicken thigh")

        coordinator.rename(id, to: "   ") // blank ignored
        XCTAssertEqual(coordinator.review?.items.first?.request.name, "chicken thigh")
    }
}
