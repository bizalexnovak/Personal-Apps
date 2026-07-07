import XCTest
import SwiftData
@testable import MacroLog

/// Exercises the clarify-before-save flow with parser fixtures shaped like
/// Claude's responses for: "a bag of popcorn", "some rice", "a Chobani
/// yogurt", "a bowl of cereal".
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

    private func makeCoordinator(parsed: [FoodItemRequest]) -> MealCaptureCoordinator {
        let coordinator = MealCaptureCoordinator()
        coordinator.parser = MockMealParser(result: parsed)
        coordinator.logger = MealLoggingService(
            parser: MockMealParser(result: parsed),
            nutrition: MockNutritionLookup(matches: [:]) // fail-soft zeros; macros aren't under test here
        )
        return coordinator
    }

    private func savedMeals(in context: ModelContext) throws -> [Meal] {
        try context.fetch(FetchDescriptor<Meal>())
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

    // MARK: - Tests

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
        let coordinator = makeCoordinator(parsed: [flaggedChobani])

        await coordinator.begin(text: "a Chobani yogurt", in: context)
        let pending = try XCTUnwrap(coordinator.pendingClarification)

        await coordinator.choose(pending.options[0])

        XCTAssertNil(coordinator.pendingClarification)
        let meals = try savedMeals(in: context)
        XCTAssertEqual(meals.count, 1)
        let item = try XCTUnwrap(meals.first?.items.first)
        XCTAssertEqual(item.name, "Chobani non-fat plain greek yogurt")
        XCTAssertEqual(item.quantity, 1)
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
        let coordinator = makeCoordinator(parsed: [unflaggedSomeRice])

        await coordinator.begin(text: "some rice", in: context)
        XCTAssertNotNil(coordinator.pendingClarification)

        await coordinator.keepAsHeard()

        let meals = try savedMeals(in: context)
        XCTAssertEqual(meals.count, 1)
        let item = try XCTUnwrap(meals.first?.items.first)
        XCTAssertEqual(item.unit, "some")
        // Lookup failed (empty mock) → fail-soft zeros with the review flag.
        XCTAssertEqual(item.matchConfidence, MatchConfidence.low)
    }

    func testUnambiguousItemsSaveWithoutPrompt() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [clearEggs])

        await coordinator.begin(text: "two eggs", in: context)

        XCTAssertNil(coordinator.pendingClarification)
        XCTAssertEqual(try savedMeals(in: context).count, 1)
    }

    func testMixedMealOnlyPromptsForAmbiguousItem() async throws {
        let context = try makeContext()
        let coordinator = makeCoordinator(parsed: [clearEggs, flaggedCerealBowl])

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
}
