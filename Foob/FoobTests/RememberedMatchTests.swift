import XCTest
import SwiftData
@testable import Foob

/// Req 2: a user's search-pick correction is remembered and reused for the
/// same phrase on future logs, skipping the faulty search.
@MainActor
final class RememberedMatchTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(AppModelContainer.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private var celsiusFood: USDAFood {
        USDAFood(
            fdcId: 999,
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

    // MARK: - Store round-trip

    func testStoreRemembersAndNormalizesPhrase() throws {
        let context = try makeContext()
        RememberedMatchStore.remember(phrase: "Celsius Energy Drink", food: celsiusFood, in: context)

        // Different casing/spacing must hit the same entry.
        let found = RememberedMatchStore.lookup(phrase: "celsius  energy drink", in: context)
        XCTAssertEqual(found?.fdcId, 999)
        XCTAssertEqual(found?.description, celsiusFood.description)
    }

    func testRememberUpsertsRatherThanDuplicating() throws {
        let context = try makeContext()
        RememberedMatchStore.remember(phrase: "celsius energy drink", food: celsiusFood, in: context)
        RememberedMatchStore.remember(phrase: "celsius energy drink", food: celsiusFood, in: context)

        let rows = try context.fetch(FetchDescriptor<RememberedMatch>())
        XCTAssertEqual(rows.count, 1, "re-remembering a phrase updates the existing row")
    }

    // MARK: - Coordinator reuse

    func testPickedCorrectionIsReusedOnNextLog() async throws {
        let context = try makeContext()
        let parsed = [FoodItemRequest(name: "Celsius energy drink", quantity: 1, unit: "can")]

        func freshCoordinator() -> MealCaptureCoordinator {
            let c = MealCaptureCoordinator()
            c.parser = MockMealParser(result: parsed)
            // Empty matches → the live search finds nothing; only a remembered
            // correction can produce a match.
            c.logger = MealLoggingService(
                parser: MockMealParser(result: parsed),
                nutrition: MockNutritionLookup(matches: [:])
            )
            return c
        }

        // First log: no match, user searches and picks the real Celsius entry.
        let first = freshCoordinator()
        await first.begin(text: "I drank one can of celsius", in: context)
        let firstItem = try XCTUnwrap(first.review?.items.first)
        XCTAssertNil(firstItem.match, "no live match available")
        first.applyPickedFood(firstItem.id, food: celsiusFood)
        await first.saveAll()

        // Second log of the same phrase: the remembered correction is used
        // automatically, even though live search still returns nothing.
        let second = freshCoordinator()
        await second.begin(text: "celsius energy drink", in: context)
        let secondItem = try XCTUnwrap(second.review?.items.first)
        let match = try XCTUnwrap(secondItem.match, "remembered correction should produce a match")
        XCTAssertEqual(match.calories, 9.94, accuracy: 0.1, "355 ml can × 2.8 kcal/100ml")
        XCTAssertTrue(match.matchedDescription.contains("CELSIUS"))
    }
}
