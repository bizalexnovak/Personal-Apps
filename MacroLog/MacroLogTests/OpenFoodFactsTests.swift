import XCTest
@testable import MacroLog

final class OpenFoodFactsTests: XCTestCase {
    private func decode(_ json: String) throws -> [OpenFoodFactsService.Product] {
        try JSONDecoder().decode(
            OpenFoodFactsService.SearchResponse.self,
            from: json.data(using: .utf8)!
        ).products ?? []
    }

    func testPerServingValuesPreferred() throws {
        let products = try decode("""
        {"products": [{
            "product_name": "Nutella", "brands": "Ferrero",
            "serving_size": "15 g",
            "nutriments": {
                "energy-kcal_serving": 80, "proteins_serving": 1,
                "carbohydrates_serving": 8.5, "fat_serving": 4.6,
                "sugars_serving": 8.4,
                "energy-kcal_100g": 539, "proteins_100g": 6.3
            }
        }]}
        """)
        let match = OpenFoodFactsService.match(
            for: FoodItemRequest(name: "nutella", quantity: 1, unit: "serving"),
            products: products
        )
        XCTAssertEqual(match?.calories ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(match?.micros.totalSugars ?? 0, 8.4, accuracy: 0.001)
        XCTAssertEqual(match?.confidence, MatchConfidence.low)
        XCTAssertTrue(match?.matchedDescription.contains("Open Food Facts") ?? false)
    }

    func testFallsBackToPer100gAndParsesStringNumbers() throws {
        // Contributors sometimes enter numbers as strings — both must parse.
        let products = try decode("""
        {"products": [{
            "product_name": "Mystery Snack", "brands": "",
            "nutriments": {
                "energy-kcal_100g": "450", "proteins_100g": "5.5",
                "carbohydrates_100g": 60, "fat_100g": 20
            }
        }]}
        """)
        let match = OpenFoodFactsService.match(
            for: FoodItemRequest(name: "mystery snack", quantity: 200, unit: "g"),
            products: products
        )
        // Weight request → one 100 g serving (portion slider adjusts from there).
        XCTAssertEqual(match?.calories ?? 0, 450, accuracy: 0.001)
        XCTAssertEqual(match?.protein ?? 0, 5.5, accuracy: 0.001)
        XCTAssertTrue(match?.matchedDescription.contains("100 g") ?? false)
    }

    func testCountableUnitsScaleAndSodiumConverts() throws {
        let products = try decode("""
        {"products": [{
            "product_name": "Cola", "brands": "Acme",
            "serving_size": "330 ml",
            "nutriments": {
                "energy-kcal_serving": 139, "sodium_serving": 0.04,
                "caffeine_serving": 0.032
            }
        }]}
        """)
        let match = OpenFoodFactsService.match(
            for: FoodItemRequest(name: "acme cola", quantity: 2, unit: "cans"),
            products: products
        )
        XCTAssertEqual(match?.calories ?? 0, 278, accuracy: 0.001)
        // OFF grams → app milligrams, then × 2 servings.
        XCTAssertEqual(match?.micros.sodium ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(match?.micros.caffeine ?? 0, 64, accuracy: 0.001)
    }

    func testSkipsProductsWithoutCalories() throws {
        let products = try decode("""
        {"products": [
            {"product_name": "No data", "nutriments": {"proteins_100g": 5}},
            {"product_name": "Has data", "nutriments": {"energy-kcal_100g": 100}}
        ]}
        """)
        let match = OpenFoodFactsService.match(
            for: FoodItemRequest(name: "thing", quantity: 1, unit: "serving"),
            products: products
        )
        XCTAssertTrue(match?.matchedDescription.contains("Has data") ?? false)
        XCTAssertNil(OpenFoodFactsService.match(
            for: FoodItemRequest(name: "thing", quantity: 1, unit: "serving"),
            products: []
        ))
    }
}
