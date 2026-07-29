import XCTest
import SwiftData
@testable import MacroLog

@MainActor
final class CustomFoodTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppModelContainer.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    // MARK: Dedup key

    func testNameKeyIgnoresOrderCaseAndPunctuation() {
        XCTAssertEqual(
            CustomFoodStore.nameKey(name: "Corona Extra", brand: "Corona"),
            CustomFoodStore.nameKey(name: "corona EXTRA!", brand: "Corona")
        )
        XCTAssertEqual(
            CustomFoodStore.nameKey(name: "Big Mac", brand: "McDonald's"),
            CustomFoodStore.nameKey(name: "mac big", brand: "mcdonalds")
        )
    }

    func testAddIfNewRejectsDuplicates() throws {
        let context = try makeContext()
        XCTAssertTrue(CustomFoodStore.addIfNew(
            CustomFood(name: "Big Mac", brand: "McDonald's", calories: 550, source: "scan"),
            in: context
        ))
        XCTAssertFalse(CustomFoodStore.addIfNew(
            CustomFood(name: "big mac", brand: "McDonalds", calories: 550, source: "community"),
            in: context
        ), "same product from another source must not duplicate")
    }

    // MARK: Matching

    func testMatchRequiresAllQueryTokens() throws {
        let context = try makeContext()
        CustomFoodStore.addIfNew(
            CustomFood(name: "Corona Extra", brand: "Corona", serving: "12 fl oz",
                       calories: 148, carbs: 13.9, source: "seed"),
            in: context
        )
        let hit = CustomFoodStore.match(
            for: FoodItemRequest(name: "corona extra", quantity: 1, unit: "bottle"),
            in: context
        )
        XCTAssertEqual(hit?.calories ?? 0, 148, accuracy: 0.001)

        // "corona sunset" has a token the row doesn't → no match (USDA's job).
        XCTAssertNil(CustomFoodStore.match(
            for: FoodItemRequest(name: "corona sunset", quantity: 1, unit: "bottle"),
            in: context
        ))
    }

    func testCountableUnitsScaleServings() throws {
        let context = try makeContext()
        CustomFoodStore.addIfNew(
            CustomFood(name: "Corona Extra", brand: "Corona", serving: "12 fl oz",
                       calories: 148, source: "seed"),
            in: context
        )
        let two = CustomFoodStore.match(
            for: FoodItemRequest(name: "corona extra", quantity: 2, unit: "bottles"),
            in: context
        )
        XCTAssertEqual(two?.calories ?? 0, 296, accuracy: 0.001)

        // Weight/volume quantities don't multiply serving-based rows.
        let oz = CustomFoodStore.match(
            for: FoodItemRequest(name: "corona extra", quantity: 12, unit: "oz"),
            in: context
        )
        XCTAssertEqual(oz?.calories ?? 0, 148, accuracy: 0.001)
    }

    func testTightestNameWins() throws {
        let context = try makeContext()
        CustomFoodStore.addIfNew(
            CustomFood(name: "Corona Extra", brand: "Corona", calories: 148, source: "seed"),
            in: context
        )
        CustomFoodStore.addIfNew(
            CustomFood(name: "Corona Extra Oro Golden Lager Limited", brand: "Corona",
                       calories: 90, source: "seed"),
            in: context
        )
        let hit = CustomFoodStore.bestRow(for: "corona extra", in: context)
        XCTAssertEqual(hit?.calories ?? 0, 148, accuracy: 0.001)
    }

    // MARK: CSV import

    func testCSVImportWithMicrosAndDedup() throws {
        let context = try makeContext()
        let csv = """
        name,brand,serving,calories,protein,carbs,fat,caffeine
        Celsius Sparkling Orange,Celsius,12 fl oz,10,0,2,0,200
        "Latte, oat milk",Blue Bottle,16 fl oz,180,8,16,9,150
        """
        let first = try CustomFoodStore.importCSV(csv, in: context)
        XCTAssertEqual(first.added, 2)
        XCTAssertEqual(first.skipped, 0)

        let celsius = CustomFoodStore.bestRow(for: "celsius sparkling orange", in: context)
        let micros = celsius?.microsData.flatMap {
            try? JSONDecoder().decode(Micronutrients.self, from: $0)
        }
        XCTAssertEqual(micros?.caffeine ?? 0, 200, accuracy: 0.001)

        // Re-importing the same sheet adds nothing.
        let second = try CustomFoodStore.importCSV(csv, in: context)
        XCTAssertEqual(second.added, 0)
        XCTAssertEqual(second.skipped, 2)
    }

    func testCSVRejectsMissingHeader() throws {
        let context = try makeContext()
        XCTAssertThrowsError(
            try CustomFoodStore.importCSV("food,kcal\nBig Mac,550", in: context)
        )
    }

    func testParseCSVHandlesQuotesAndEscapes() {
        let rows = CustomFoodStore.parseCSV("a,\"b, with comma\",\"he said \"\"hi\"\"\"\nc,d,e")
        XCTAssertEqual(rows[0], ["a", "b, with comma", "he said \"hi\""])
        XCTAssertEqual(rows[1], ["c", "d", "e"])
    }

    // MARK: Scan capture + seed

    func testScanAddsToDatabaseOnce() throws {
        let context = try makeContext()
        var label = LabelNutrition(
            name: "", servingSize: "1 can (12 fl oz)",
            calories: 10, protein: 0, carbs: 2, fat: 0
        )
        label.caffeine = 200
        CustomFoodStore.addFromScan(name: "Celsius energy drink", label: label, in: context)
        CustomFoodStore.addFromScan(name: "celsius ENERGY drink", label: label, in: context)
        let all = try context.fetch(FetchDescriptor<CustomFood>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.source, "scan")
        XCTAssertFalse(all.first?.synced ?? true, "scans start unsynced (pending push)")
    }

    func testSeedInsertsOnceAndMatchesBeer() throws {
        let context = try makeContext()
        let defaults = UserDefaults(suiteName: "custom-food-seed-tests-\(UUID().uuidString)")!
        CustomFoodSeed.seedIfNeeded(in: context, defaults: defaults)
        let count = try context.fetch(FetchDescriptor<CustomFood>()).count
        XCTAssertEqual(count, CustomFoodSeed.count)
        CustomFoodSeed.seedIfNeeded(in: context, defaults: defaults)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CustomFood>()).count, count)

        let match = CustomFoodStore.match(
            for: FoodItemRequest(name: "michelob ultra", quantity: 2, unit: "cans"),
            in: context
        )
        XCTAssertEqual(match?.calories ?? 0, 190, accuracy: 0.001)
    }
}
