import Foundation
import SwiftData

/// Shared coders for FoodItem.microsData — the getter runs in per-render
/// aggregation loops, so it shouldn't allocate a fresh JSONDecoder per call.
private enum MicrosCoding {
    static let decoder = JSONDecoder()
    static let encoder = JSONEncoder()
}

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
    /// Fluid ounces of water in this meal (water items only).
    var waterOunces: Double { items.reduce(0) { $0 + WaterConversion.ounces(for: $1) } }

    /// All five totals in a single pass over the items. The aggregation screens
    /// (Today, Trends, the widget snapshot) sum many meals per render — use this
    /// there instead of five separate per-total passes.
    var totals: MealTotals {
        var t = MealTotals()
        for item in items {
            t.calories += item.calories
            t.protein += item.protein
            t.carbs += item.carbs
            t.fat += item.fat
            t.waterOunces += WaterConversion.ounces(for: item)
        }
        return t
    }

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
    /// Micronutrients for this entry's portion, JSON-encoded. Stored as Data so
    /// adding new micronutrient fields later needs no schema migration; access
    /// it through the `micros` computed property below.
    var microsData: Data?
    var meal: Meal?

    /// Decoded micronutrients (fat/carb breakdown, minerals, vitamins).
    /// Computed — not itself persisted; it reads/writes `microsData`.
    var micros: Micronutrients {
        get {
            guard let microsData,
                  let decoded = try? MicrosCoding.decoder.decode(Micronutrients.self, from: microsData)
            else { return .empty }
            return decoded
        }
        set {
            microsData = newValue.isEmpty ? nil : (try? MicrosCoding.encoder.encode(newValue))
        }
    }

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

/// A meal's five running totals, accumulated in one pass (see `Meal.totals`).
struct MealTotals {
    var calories = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
    var waterOunces = 0.0
}
