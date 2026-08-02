import XCTest
@testable import Foob

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

/// The on-device fallback parser used when the Claude API is unreachable.
final class LocalMealParserTests: XCTestCase {
    func testQuantityUnitAndName() {
        let items = LocalMealParser.parse("24 oz of water")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "water")
        XCTAssertEqual(items[0].quantity, 24, accuracy: 0.001)
        XCTAssertEqual(items[0].unit, "oz")
    }

    func testNumberWordsAndContainers() {
        let items = LocalMealParser.parse("a bottle of water")
        XCTAssertEqual(items[0].name, "water")
        XCTAssertEqual(items[0].quantity, 1, accuracy: 0.001)
        XCTAssertEqual(items[0].unit, "bottle")
    }

    func testBareSupplementParses() {
        let items = LocalMealParser.parse("5 grams of creatine")
        XCTAssertEqual(items[0].name, "creatine")
        XCTAssertEqual(items[0].quantity, 5, accuracy: 0.001)
        XCTAssertEqual(items[0].unit, "grams")
    }

    func testSplitsOnCommasAndAnd() {
        let items = LocalMealParser.parse("two eggs and a slice of toast")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "eggs")
        XCTAssertEqual(items[0].quantity, 2, accuracy: 0.001)
        XCTAssertEqual(items[1].name, "toast")
        XCTAssertEqual(items[1].unit, "slice")
    }

    func testSpokenMacrosAttachToTheirItem() {
        let items = LocalMealParser.parse("chicken, 300 calories and 30 grams of protein")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "chicken")
        XCTAssertEqual(items[0].calories, 300)
        XCTAssertEqual(items[0].protein, 30)
        XCTAssertTrue(items[0].hasExplicitMacros)
    }

    func testStripsLeadingVerbs() {
        let items = LocalMealParser.parse("I drank a glass of water")
        XCTAssertEqual(items[0].name, "water")
        XCTAssertEqual(items[0].unit, "glass")
    }

    func testNeverReturnsEmptyForNonEmptyText() {
        let items = LocalMealParser.parse("something unusual")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "something unusual")
        XCTAssertEqual(items[0].quantity, 1, accuracy: 0.001)
        XCTAssertEqual(items[0].unit, "serving")
    }

    func testEmptyTextReturnsNothing() {
        XCTAssertTrue(LocalMealParser.parse("   ").isEmpty)
    }

    func testLeadingMacrosAttachToTheNextItem() {
        // Macros spoken before the item ("300 calories, chicken") must not
        // be dropped — they park and attach to the next named item.
        let items = LocalMealParser.parse("300 calories and chicken")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "chicken")
        XCTAssertEqual(items[0].calories, 300)
    }

    func testSpelledOutMacroNumbers() {
        let items = LocalMealParser.parse("chicken, eleven grams of protein")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "chicken")
        XCTAssertEqual(items[0].protein, 11)
    }

    func testMacroKeywordInProductNameIsNotAMacro() {
        // "2 protein bars" states a count, not a protein amount.
        let items = LocalMealParser.parse("2 protein bars")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "protein bars")
        XCTAssertEqual(items[0].quantity, 2, accuracy: 0.001)
        XCTAssertNil(items[0].protein)
    }

    func testArticleBetweenAmountAndUnit() {
        let items = LocalMealParser.parse("half a cup of rice")
        XCTAssertEqual(items[0].name, "rice")
        XCTAssertEqual(items[0].quantity, 0.5, accuracy: 0.001)
        XCTAssertEqual(items[0].unit, "cup")
    }

    func testLargeVolumeWaterUnits() {
        // pint/quart/gallon must be recognized so WaterConversion gets the
        // real unit instead of its 8-oz "serving" fallback.
        let items = LocalMealParser.parse("2 pints of water")
        XCTAssertEqual(items[0].name, "water")
        XCTAssertEqual(items[0].quantity, 2, accuracy: 0.001)
        XCTAssertEqual(items[0].unit, "pints")
    }

    func testMacrosOnlyPhraseStillCreatesAnEntry() {
        // The whole-phrase fallback carries parked macros instead of losing them.
        let items = LocalMealParser.parse("300 calories")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].calories, 300)
    }
}
