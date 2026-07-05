import Foundation

/// One food item as parsed out of free-form meal text by the Claude API,
/// before any nutrition lookup has happened.
struct FoodItemRequest: Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String
}

/// Wire format of the JSON object the parsing prompt asks Claude to return:
/// `{"items": [{"name": ..., "quantity": ..., "unit": ...}]}`
struct ParsedMealResponse: Codable, Equatable {
    var items: [FoodItemRequest]
}
