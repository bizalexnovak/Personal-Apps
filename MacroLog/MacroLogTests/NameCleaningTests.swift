import XCTest
@testable import MacroLog

/// Req 1: the item name must be the clean product name, never the sentence.
final class NameCleaningTests: XCTestCase {
    func testStripsFirstPersonContainerLeadIn() {
        XCTAssertEqual(ClaudeMealParsingService.cleanName("I drank one can of celsius"), "celsius")
        XCTAssertEqual(ClaudeMealParsingService.cleanName("I ate a bowl of oatmeal"), "oatmeal")
        XCTAssertEqual(ClaudeMealParsingService.cleanName("had two slices of sourdough"), "sourdough")
    }

    func testLeavesCleanProductNamesUntouched() {
        XCTAssertEqual(ClaudeMealParsingService.cleanName("Celsius energy drink"), "Celsius energy drink")
        XCTAssertEqual(ClaudeMealParsingService.cleanName("greek yogurt"), "greek yogurt")
        XCTAssertEqual(ClaudeMealParsingService.cleanName("chicken breast"), "chicken breast")
    }

    func testCollapsesWhitespaceAndNeverReturnsEmpty() {
        XCTAssertEqual(ClaudeMealParsingService.cleanName("  scrambled   eggs "), "scrambled eggs")
        // Pathological input that would strip to nothing falls back to the original.
        XCTAssertEqual(ClaudeMealParsingService.cleanName("I ate"), "I ate")
    }

    func testDecodeAppliesNameCleaning() throws {
        let json = #"{"items": [{"name": "I drank one can of celsius", "quantity": 1, "unit": "can"}]}"#
        let items = try ClaudeMealParsingService.decodeItems(from: json)
        XCTAssertEqual(items.first?.name, "celsius", "leaked sentence in name must be scrubbed on decode")
        XCTAssertEqual(items.first?.quantity, 1)
        XCTAssertEqual(items.first?.unit, "can")
    }

    func testLabelNutritionDecoding() throws {
        let json = #"{"name": "Celsius Sparkling Orange", "servingSize": "1 can (12 fl oz)", "calories": 10, "protein": 0, "carbs": 2, "fat": 0}"#
        let label = try ClaudeLabelScanningService.decode(from: json)
        XCTAssertEqual(label.name, "Celsius Sparkling Orange")
        XCTAssertEqual(label.servingSize, "1 can (12 fl oz)")
        XCTAssertEqual(label.calories, 10)
        XCTAssertEqual(label.carbs, 2)
    }
}
