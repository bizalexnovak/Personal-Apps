import Foundation
import SwiftData

@Model
final class Meal {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var rawText: String
    @Relationship(deleteRule: .cascade, inverse: \FoodItem.meal)
    var items: [FoodItem]

    init(id: UUID = UUID(), timestamp: Date = .now, rawText: String, items: [FoodItem] = []) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.items = items
    }

    var totalCalories: Double { items.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { items.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Double { items.reduce(0) { $0 + $1.carbs } }
    var totalFat: Double { items.reduce(0) { $0 + $1.fat } }

    /// Food-only summary for the meal lists: the item names joined naturally
    /// ("chicken and green beans", "eggs, toast and bacon") — not the raw
    /// transcript or a "Scanned label: …" prefix. Falls back to rawText only
    /// if there are somehow no items.
    var displayName: String {
        let names = items
            .map { $0.name.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = names.last else { return rawText }
        if names.count == 1 { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}

@Model
final class FoodItem {
    var name: String
    var quantity: Double
    var unit: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// "high" when the USDA match and unit conversion were unambiguous, "low" when the
    /// values are a guess and the item should be reviewed manually.
    var matchConfidence: String
    var meal: Meal?

    init(
        name: String,
        quantity: Double,
        unit: String,
        calories: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        matchConfidence: String = MatchConfidence.low
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.matchConfidence = matchConfidence
    }
}

enum MatchConfidence {
    static let high = "high"
    static let low = "low"
}
