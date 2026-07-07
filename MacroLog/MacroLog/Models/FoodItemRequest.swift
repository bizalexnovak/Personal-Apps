import Foundation

/// One tap-to-resolve interpretation of an ambiguous item. Each option is a
/// fully resolved replacement: tapping it substitutes name/quantity/unit.
struct ClarificationOption: Codable, Equatable, Identifiable {
    var label: String
    var name: String
    var quantity: Double
    var unit: String

    var id: String { "\(label)|\(name)|\(quantity)|\(unit)" }
}

/// One food item as parsed out of free-form meal text by the Claude API,
/// before any nutrition lookup has happened.
struct FoodItemRequest: Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String

    /// Set by the parser when the description is too vague to estimate macros
    /// reliably (vague container words, ambiguous brand, multiple possible
    /// foods). The app must resolve these via a clarification card before
    /// anything is written to SwiftData.
    var needsClarification: Bool? = nil
    var clarificationQuestion: String? = nil
    var options: [ClarificationOption]? = nil
}

/// Wire format of the JSON object the parsing prompt asks Claude to return.
struct ParsedMealResponse: Codable, Equatable {
    var items: [FoodItemRequest]
}
