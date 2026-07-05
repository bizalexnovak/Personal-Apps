import XCTest
@testable import MacroLog

final class MealParsingTests: XCTestCase {
    func testDecodesPlainJSON() throws {
        let text = """
        {"items": [{"name": "scrambled eggs", "quantity": 2, "unit": "large"}, {"name": "toast", "quantity": 1, "unit": "slice"}]}
        """
        let items = try ClaudeMealParsingService.decodeItems(from: text)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0], FoodItemRequest(name: "scrambled eggs", quantity: 2, unit: "large"))
        XCTAssertEqual(items[1].name, "toast")
    }

    func testStripsMarkdownFencesDefensively() throws {
        let text = """
        ```json
        {"items": [{"name": "oatmeal", "quantity": 1, "unit": "cup"}]}
        ```
        """
        let items = try ClaudeMealParsingService.decodeItems(from: text)
        XCTAssertEqual(items, [FoodItemRequest(name: "oatmeal", quantity: 1, unit: "cup")])
    }

    func testCutsPreambleToOutermostObject() throws {
        let text = """
        Here is the JSON: {"items": [{"name": "banana", "quantity": 1, "unit": "medium"}]}
        """
        let items = try ClaudeMealParsingService.decodeItems(from: text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "banana")
    }

    func testThrowsOnGarbage() {
        XCTAssertThrowsError(try ClaudeMealParsingService.decodeItems(from: "not json at all"))
    }
}
