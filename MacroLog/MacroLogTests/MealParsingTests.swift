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

    func testDecodesClarificationFields() throws {
        let text = """
        {"items": [{
            "name": "Chobani yogurt", "quantity": 1, "unit": "container",
            "needsClarification": true,
            "clarificationQuestion": "Which Chobani product was it?",
            "options": [
                {"label": "Plain non-fat Greek (5.3 oz cup)", "name": "Chobani non-fat plain greek yogurt", "quantity": 1, "unit": "container"},
                {"label": "Fruit on the bottom (5.3 oz cup)", "name": "Chobani fruit on the bottom greek yogurt", "quantity": 1, "unit": "container"},
                {"label": "Chobani Flip (4.5 oz)", "name": "Chobani Flip greek yogurt", "quantity": 1, "unit": "container"}
            ]
        }]}
        """
        let items = try ClaudeMealParsingService.decodeItems(from: text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].needsClarification, true)
        XCTAssertEqual(items[0].clarificationQuestion, "Which Chobani product was it?")
        XCTAssertEqual(items[0].options?.count, 3)
        XCTAssertEqual(items[0].options?.first?.name, "Chobani non-fat plain greek yogurt")
    }

    func testUnflaggedItemsDecodeWithNilClarification() throws {
        let text = """
        {"items": [{"name": "banana", "quantity": 1, "unit": "medium", "needsClarification": false, "clarificationQuestion": null, "options": null}]}
        """
        let items = try ClaudeMealParsingService.decodeItems(from: text)
        XCTAssertEqual(items[0].needsClarification, false)
        XCTAssertNil(items[0].options)
    }
}
