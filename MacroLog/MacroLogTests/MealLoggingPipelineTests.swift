import XCTest
import SwiftData
@testable import MacroLog

// MARK: - Mocks

struct MockMealParser: MealParsing {
    var result: [FoodItemRequest]
    func parse(_ mealText: String) async throws -> [FoodItemRequest] { result }
}

struct MockNutritionLookup: NutritionLookup {
    var matches: [String: NutritionMatch]

    func lookup(_ request: FoodItemRequest) async throws -> NutritionMatch {
        guard let match = matches[request.name] else {
            throw NutritionLookupError.noResults
        }
        return match
    }

    func search(query: String) async throws -> [USDAFood] { [] }
}

// MARK: - Pipeline tests

@MainActor
final class MealLoggingPipelineTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Meal.self, FoodItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    func testLogMealSavesParsedAndLookedUpItems() async throws {
        let context = try makeContext()
        let service = MealLoggingService(
            parser: MockMealParser(result: [
                FoodItemRequest(name: "chicken breast", quantity: 6, unit: "oz"),
                FoodItemRequest(name: "white rice", quantity: 1, unit: "cup"),
            ]),
            nutrition: MockNutritionLookup(matches: [
                "chicken breast": NutritionMatch(
                    matchedDescription: "Chicken breast, grilled",
                    calories: 280, protein: 52, carbs: 0, fat: 6,
                    confidence: MatchConfidence.high
                ),
                "white rice": NutritionMatch(
                    matchedDescription: "Rice, white, cooked",
                    calories: 205, protein: 4.2, carbs: 44.5, fat: 0.4,
                    confidence: MatchConfidence.high
                ),
            ])
        )

        let meal = try await service.logMeal(from: "6oz chicken and a cup of rice", in: context)

        XCTAssertEqual(meal.items.count, 2)
        XCTAssertEqual(meal.rawText, "6oz chicken and a cup of rice")
        XCTAssertEqual(meal.totalCalories, 485, accuracy: 0.01)
        XCTAssertEqual(meal.totalProtein, 56.2, accuracy: 0.01)

        let saved = try context.fetch(FetchDescriptor<Meal>())
        XCTAssertEqual(saved.count, 1)
    }

    func testFailedLookupSavesItemWithLowConfidence() async throws {
        let context = try makeContext()
        let service = MealLoggingService(
            parser: MockMealParser(result: [
                FoodItemRequest(name: "mystery casserole", quantity: 1, unit: "serving")
            ]),
            nutrition: MockNutritionLookup(matches: [:]) // every lookup fails
        )

        let meal = try await service.logMeal(from: "some casserole", in: context)

        XCTAssertEqual(meal.items.count, 1)
        let item = try XCTUnwrap(meal.items.first)
        XCTAssertEqual(item.calories, 0)
        XCTAssertEqual(item.matchConfidence, MatchConfidence.low)
    }
}
