import XCTest
import SwiftData
@testable import MacroLog

/// Exercises the clarify → lookup → resolve-or-fallback → save flow with
/// parser fixtures shaped like Claude's responses.
@MainActor
final class MealCaptureCoordinatorTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Meal.self, FoodItem.self])
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

    // MARK: - Fixtures (shaped like Claude's clarification output)

    private var flaggedPopcornBag: FoodItemRequest {
        FoodItemRequest(
            name: "popcorn", quantity: 1, unit: "bag",
            needsClarification: true,
            clarificationQuestion: "How big was the bag of popcorn?",
            options: [
                ClarificationOption(label: "Snack bag (about 1 oz)", name: "popped popcorn", quantity: 28, unit: "g"),
                ClarificationOption(label: "Whole microwave bag", name: "microwave popcorn, popped", quantity: 80, unit: "g"),
                ClarificationOption(label: "Movie-theater small", name: "movie theater popcorn", quantity: 170, unit: "g"),
            ]
        )
    }

    private var flaggedChobani: FoodItemRequest {
        FoodItemRequest(
            name: "Chobani yogurt", quantity: 1, unit: "container",
            needsClarification: true,
            clarificationQuestion: "Which Chobani product was it?",
            options: [
                ClarificationOption(label: "Plain non-fat Greek (5.3 oz)", name: "Chobani non-fat plain greek yogurt", quantity: 1, unit: "container"),
                ClarificationOption(label: "Fruit on the bottom (5.3 oz)", name: "Chobani fruit on the bottom greek yogurt", quantity: 1, unit: "container"),
                ClarificationOption(label: "Chobani Flip (4.5 oz)", name: "Chobani Flip greek yogurt", quantity: 1, unit: "container"),
            ]
        )
    }

    private var flaggedCerealBowl: FoodItemRequest {
        FoodItemRequest(
            name: "cereal", quantity: 1, unit: "bowl",
            needsClarification: true,
            clarificationQuestion: "What cereal, and how big a bowl?",
            options: [
                ClarificationOption(label: "Cheerios, small bowl", name: "Cheerios cereal", quantity: 1, unit: "cup"),
                ClarificationOption(label: "Cheerios, large bowl", name: "Cheerios cereal", quantity: 2, unit: "cup"),
                ClarificationOption(label: "Granola, small bowl", name: "granola cereal", quantity: 0.5, unit: "cup"),
            ]
        )
    }

    /// "some rice" — parser did NOT flag it; the local vague-unit safety net must.
    private var unflaggedSomeRice: FoodItemRequest {
        FoodItemRequest(name: "rice", quantity: 1, unit: "some")
    }

    private var clearEggs: FoodItemRequest {
        FoodItemRequest(name: "eggs", quantity: 2, unit: "large")
    }

    private var celsiusDrink: FoodItemRequest {
        FoodItemRequest(name: "Celsius energy drink", quantity: 1, unit: "can")
    }

    private var goldfishCrackers: FoodItemRequest {
        FoodItemRequest(name: "Goldfish crackers", quantity: 1, unit: "serving")
    }

    // MARK: - Clarification phase

    func testFlaggedItemPausesBeforeAnythingIsSaved() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [flaggedPopcornBag])

        await coordinator.begin(text: "a bag of popcorn", in: context)

        let pending = try XCTUnwrap(coordinator.pendingClarification)
        XCTAssertEqual(pending.question, "How big was the bag of popcorn?")
        XCTAssertEqual(pending.options.count, 3)
        XCTAssertTrue(try savedMeals(in: context).isEmpty, "nothing may hit SwiftData while clarification is pending")
    }

    func testChoosingOptionResolvesItemAndSaves() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [flaggedChobani],
            matches: ["Chobani non-fat plain greek yogurt": match("CHOBANI NON-FAT GREEK YOGURT PLAIN", kcal: 97, protein: 17.3)]
        )

        await coordinator.begin(text: "a Chobani yogurt", in: context)
        let pending = try XCTUnwrap(coordinator.pendingClarification)

        await coordinator.choose(pending.options[0])

        XCTAssertNil(coordinator.pendingClarification)
        let meals = try savedMeals(in: context)
        XCTAssertEqual(meals.count, 1)
        let item = try XCTUnwrap(meals.first?.items.first)
        XCTAssertEqual(item.name, "Chobani non-fat plain greek yogurt")
        XCTAssertEqual(item.calories, 97, accuracy: 0.01)
        XCTAssertEqual(item.unit, "container")
    }

    func testVagueUnitTriggersLocalFallbackPrompt() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [unflaggedSomeRice])

        await coordinator.begin(text: "some rice", in: context)

        let pending = try XCTUnwrap(
            coordinator.pendingClarification,
            "'some' must trigger clarification even when the parser didn't flag it"
        )
        XCTAssertTrue(pending.question.contains("rice"))
        XCTAssertEqual(pending.options.count, 3)
        XCTAssertTrue(pending.options.allSatisfy { $0.unit == "g" })
        XCTAssertTrue(try savedMeals(in: context).isEmpty)
    }

    func testKeepAsHeardSavesOriginalItem() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [unflaggedSomeRice],
            matches: ["rice": match("Rice, white, cooked", kcal: 130, confidence: MatchConfidence.low)]
        )

        await coordinator.begin(text: "some rice", in: context)
        XCTAssertNotNil(coordinator.pendingClarification)

        await coordinator.keepAsHeard()

        let meals = try savedMeals(in: context)
        XCTAssertEqual(meals.count, 1)
        let item = try XCTUnwrap(meals.first?.items.first)
        XCTAssertEqual(item.unit, "some")
        XCTAssertEqual(item.matchConfidence, MatchConfidence.low)
    }

    func testUnambiguousItemsSaveWithoutPrompt() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [clearEggs],
            matches: ["eggs": match("GRADE A LARGE EGGS", kcal: 143, protein: 12.6)]
        )

        await coordinator.begin(text: "two eggs", in: context)

        XCTAssertNil(coordinator.pendingClarification)
        XCTAssertNil(coordinator.pendingResolution)
        XCTAssertEqual(try savedMeals(in: context).count, 1)
    }

    func testMixedMealOnlyPromptsForAmbiguousItem() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [clearEggs, flaggedCerealBowl],
            matches: [
                "eggs": match("GRADE A LARGE EGGS", kcal: 143),
                "Cheerios cereal": match("CHEERIOS", kcal: 210),
            ]
        )

        await coordinator.begin(text: "two eggs and a bowl of cereal", in: context)
        let pending = try XCTUnwrap(coordinator.pendingClarification)
        XCTAssertEqual(pending.item.name, "cereal")

        await coordinator.choose(pending.options[1])

        let meals = try savedMeals(in: context)
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals.first?.items.count, 2)
        let cereal = try XCTUnwrap(meals.first?.items.first { $0.name.contains("Cheerios") })
        XCTAssertEqual(cereal.quantity, 2)
        XCTAssertEqual(cereal.unit, "cup")
    }

    func testCancelMealSavesNothing() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [flaggedPopcornBag])

        await coordinator.begin(text: "a bag of popcorn", in: context)
        XCTAssertNotNil(coordinator.pendingClarification)

        coordinator.cancelMeal()

        XCTAssertNil(coordinator.pendingClarification)
        XCTAssertFalse(coordinator.isCapturing)
        XCTAssertTrue(try savedMeals(in: context).isEmpty)
    }

    func testLocalFallbackOptionsScaleWithQuantity() {
        let item = FoodItemRequest(name: "chips", quantity: 2, unit: "bag")
        let options = MealCaptureCoordinator.fallbackOptions(for: item, vagueWord: "bag")
        XCTAssertEqual(options.first?.quantity, 56, "2 bags × 28 g snack bag")
    }

    // MARK: - No-match fallback (lookup phase)

    func testNoMatchPausesOnManualResolutionInsteadOfSavingZeros() async throws {
        let context = try makeContext()
        // Empty matches: every lookup throws noResults, like the FDC returning nothing.
        let coordinator = makeCoordinator(parsed: [celsiusDrink])

        await coordinator.begin(text: "a Celsius energy drink", in: context)

        let resolution = try XCTUnwrap(coordinator.pendingResolution)
        XCTAssertEqual(resolution.request.name, "Celsius energy drink")
        XCTAssertTrue(try savedMeals(in: context).isEmpty, "a failed match must never save a zero-calorie entry")
    }

    func testResolveManuallySavesEnteredValues() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [celsiusDrink])

        await coordinator.begin(text: "a Celsius energy drink", in: context)
        XCTAssertNotNil(coordinator.pendingResolution)

        await coordinator.resolveManually(match("Manual entry", kcal: 10))

        XCTAssertNil(coordinator.pendingResolution)
        let meals = try savedMeals(in: context)
        XCTAssertEqual(meals.count, 1)
        let item = try XCTUnwrap(meals.first?.items.first)
        XCTAssertEqual(item.calories, 10, accuracy: 0.01, "the entered value must be saved, not zero")
        XCTAssertEqual(item.name, "Celsius energy drink")
    }

    func testSkipUnmatchedItemKeepsRestOfMeal() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(
            parsed: [clearEggs, goldfishCrackers],
            matches: ["eggs": match("GRADE A LARGE EGGS", kcal: 143)] // Goldfish finds nothing
        )

        await coordinator.begin(text: "two eggs and Goldfish crackers", in: context)
        let resolution = try XCTUnwrap(coordinator.pendingResolution)
        XCTAssertEqual(resolution.request.name, "Goldfish crackers")

        await coordinator.skipUnmatchedItem()

        let meals = try savedMeals(in: context)
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals.first?.items.count, 1)
        XCTAssertEqual(meals.first?.items.first?.name, "eggs")
    }

    func testSkippingOnlyItemSavesNoMeal() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [goldfishCrackers])

        await coordinator.begin(text: "Goldfish", in: context)
        XCTAssertNotNil(coordinator.pendingResolution)

        await coordinator.skipUnmatchedItem()

        XCTAssertTrue(try savedMeals(in: context).isEmpty)
        XCTAssertNotNil(coordinator.errorMessage, "user should hear that nothing was logged")
    }
}
