import XCTest
import SwiftData
@testable import Foob

final class RecipeSearchSupportTests: XCTestCase {
    func testSplitMeasureParsesNumbersAndFractions() {
        XCTAssertEqual(RecipeSearchSupport.splitMeasure("1 1/2 cups").quantity, 1.5, accuracy: 0.001)
        XCTAssertEqual(RecipeSearchSupport.splitMeasure("1 1/2 cups").unit, "cups")
        XCTAssertEqual(RecipeSearchSupport.splitMeasure("1/2 cup").quantity, 0.5, accuracy: 0.001)
        XCTAssertEqual(RecipeSearchSupport.splitMeasure("2 tbsp").quantity, 2, accuracy: 0.001)
        XCTAssertEqual(RecipeSearchSupport.splitMeasure("1 lb").unit, "lb")
    }

    func testSplitMeasureFallsBackWhenNoNumber() {
        XCTAssertEqual(RecipeSearchSupport.splitMeasure("").quantity, 1, accuracy: 0.001)
        XCTAssertEqual(RecipeSearchSupport.splitMeasure("").unit, "serving")
        XCTAssertEqual(RecipeSearchSupport.splitMeasure("to taste").quantity, 1, accuracy: 0.001)
        XCTAssertEqual(RecipeSearchSupport.splitMeasure("to taste").unit, "to taste")
    }

    func testSlotGuessFromTitleAndTags() {
        XCTAssertEqual(RecipeSearchSupport.slot(title: "Blueberry Pancakes", tags: []), .breakfast)
        XCTAssertEqual(RecipeSearchSupport.slot(title: "Chicken Caesar Salad", tags: ["lunch"]), .lunch)
        XCTAssertEqual(RecipeSearchSupport.slot(title: "Beef Stir-Fry", tags: ["dinner"]), .dinner)
        XCTAssertEqual(RecipeSearchSupport.slot(title: "Chocolate Cake", tags: ["Dessert"]), .snack)
        XCTAssertEqual(RecipeSearchSupport.slot(title: "Mystery Dish", tags: []), .any)
    }

    func testStrippingHTMLRemovesTagsAndCollapsesWhitespace() {
        XCTAssertEqual(
            RecipeSearchSupport.strippingHTML("<ol><li>Chop.</li><li>Cook.</li></ol>"),
            "Chop. Cook."
        )
        XCTAssertEqual(RecipeSearchSupport.strippingHTML("plain text"), "plain text")
        XCTAssertEqual(RecipeSearchSupport.strippingHTML(""), "")
    }
}

/// Stub lookup so import tests don't hit the network.
private struct StubLookup: NutritionLookup {
    var perRequest: NutritionMatch
    var onCalled: (() -> Void)?
    func lookup(_ request: FoodItemRequest) async throws -> NutritionMatch {
        onCalled?()
        return perRequest
    }
    func search(query: String) async throws -> [USDAFood] { [] }
}

@MainActor
final class RecipeImporterTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppModelContainer.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testImportScalesToSingleServingAndFillsMacros() async throws {
        let context = try makeContext()
        let result = RecipeSearchResult(
            id: "x", title: "Test Dish", sourceName: "TheMealDB", imageURL: nil,
            servings: 2, slot: .dinner,
            ingredients: [ImportIngredient(name: "beef", quantity: 8, unit: "oz")],
            previewPerServing: nil
        )
        let stub = StubLookup(perRequest: NutritionMatch(
            matchedDescription: "beef", calories: 100, protein: 20, carbs: 0, fat: 3,
            confidence: MatchConfidence.high
        ))
        let recipe = await RecipeImporter.makeRecipe(from: result, lookup: stub, into: context)

        XCTAssertEqual(recipe.ingredientList.count, 1)
        // 8 oz over 2 servings → 4 oz per serving.
        XCTAssertEqual(recipe.ingredientList.first?.quantity ?? 0, 4, accuracy: 0.001)
        // Macros came from the (USDA) lookup for the single-serving portion.
        XCTAssertEqual(recipe.ingredientList.first?.calories ?? 0, 100, accuracy: 0.001)
    }

    func testImportUsesProviderMacrosWithoutLookup() async throws {
        let context = try makeContext()
        let result = RecipeSearchResult(
            id: "y", title: "Provider Dish", sourceName: "Spoonacular", imageURL: nil,
            servings: 2, slot: .lunch,
            ingredients: [ImportIngredient(
                name: "chicken", quantity: 12, unit: "oz",
                calories: 400, protein: 80, carbs: 0, fat: 8
            )],
            previewPerServing: nil
        )
        var lookupCalled = false
        let stub = StubLookup(
            perRequest: NutritionMatch(matchedDescription: "x", calories: 999,
                                       protein: 0, carbs: 0, fat: 0, confidence: MatchConfidence.low),
            onCalled: { lookupCalled = true }
        )
        let recipe = await RecipeImporter.makeRecipe(from: result, lookup: stub, into: context)

        XCTAssertFalse(lookupCalled, "provider macros were present — no USDA call expected")
        // 400 kcal over 2 servings → 200 per serving (not the stub's 999).
        XCTAssertEqual(recipe.ingredientList.first?.calories ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(recipe.ingredientList.first?.protein ?? 0, 40, accuracy: 0.001)
    }

    func testImportCarriesInstructions() async throws {
        let context = try makeContext()
        var result = RecipeSearchResult(
            id: "z", title: "Stew", sourceName: "TheMealDB", imageURL: nil,
            servings: 1, slot: .dinner,
            ingredients: [ImportIngredient(
                name: "beef", quantity: 1, unit: "lb",
                calories: 800, protein: 90, carbs: 0, fat: 45
            )],
            previewPerServing: nil
        )
        result.instructions = "1. Brown the beef.\n2. Simmer 2 hours."
        let stub = StubLookup(perRequest: NutritionMatch(
            matchedDescription: "x", calories: 0, protein: 0, carbs: 0, fat: 0,
            confidence: MatchConfidence.low
        ))
        let recipe = await RecipeImporter.makeRecipe(from: result, lookup: stub, into: context)
        XCTAssertEqual(recipe.instructions, "1. Brown the beef.\n2. Simmer 2 hours.")
    }
}
