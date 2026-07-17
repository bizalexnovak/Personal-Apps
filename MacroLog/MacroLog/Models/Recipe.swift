import Foundation
import SwiftData

/// A saved, reusable meal template: a named list of ingredients with known
/// macros/micros. Logging a recipe stamps a fresh `Meal` copy into the diary —
/// the recipe itself never appears in the diary or the day's totals.
@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient]

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, ingredients: [RecipeIngredient] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.ingredients = ingredients
    }

    var totalCalories: Double { ingredients.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { ingredients.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Double { ingredients.reduce(0) { $0 + $1.carbs } }
    var totalFat: Double { ingredients.reduce(0) { $0 + $1.fat } }

    /// SwiftData to-many relationships are UNORDERED — the array can come back
    /// in any order after a refetch. Every display/index-based use must go
    /// through this stable ordering (sortOrder, assigned at creation).
    var sortedIngredients: [RecipeIngredient] {
        ingredients.sorted {
            $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.name < $1.name
        }
    }

    /// The next sortOrder for an ingredient appended to this recipe.
    var nextSortOrder: Int {
        (ingredients.map(\.sortOrder).max() ?? -1) + 1
    }

    /// A fresh diary entry (timestamped now) built from this recipe. The
    /// original match confidence carries through, so unverified estimates
    /// keep their needs-a-look flag when re-logged.
    func makeMeal() -> Meal {
        let items = sortedIngredients.map { ingredient in
            let item = FoodItem(
                name: ingredient.name, quantity: ingredient.quantity, unit: ingredient.unit,
                calories: ingredient.calories, protein: ingredient.protein,
                carbs: ingredient.carbs, fat: ingredient.fat,
                matchConfidence: ingredient.matchConfidence
            )
            item.microsData = ingredient.microsData
            return item
        }
        return Meal(timestamp: .now, rawText: name, items: items)
    }

    /// A recipe captured from an already-logged meal (its items as they are).
    static func from(meal: Meal, named name: String) -> Recipe {
        let ingredients = meal.items.enumerated().map { index, item in
            RecipeIngredient(
                name: item.name, quantity: item.quantity, unit: item.unit,
                calories: item.calories, protein: item.protein,
                carbs: item.carbs, fat: item.fat,
                matchConfidence: item.matchConfidence,
                microsData: item.microsData,
                sortOrder: index
            )
        }
        return Recipe(name: name, ingredients: ingredients)
    }
}

/// One ingredient of a recipe — a snapshot of name/portion/macros/micros,
/// independent of the diary's `FoodItem`s so editing a recipe never touches
/// logged history (and vice versa).
@Model
final class RecipeIngredient {
    var name: String
    var quantity: Double
    var unit: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// Carried from the source FoodItem so a recipe round-trip can't launder
    /// a low-confidence estimate into a "verified" entry. Manually entered
    /// ingredients are high — the user typed the numbers.
    var matchConfidence: String = MatchConfidence.high
    /// Micronutrients JSON, same encoding as `FoodItem.microsData`.
    var microsData: Data?
    /// Stable display position (the relationship array itself is unordered).
    var sortOrder: Int = 0
    var recipe: Recipe?

    init(
        name: String,
        quantity: Double = 1,
        unit: String = "serving",
        calories: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        matchConfidence: String = MatchConfidence.high,
        microsData: Data? = nil,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.matchConfidence = matchConfidence
        self.microsData = microsData
        self.sortOrder = sortOrder
    }
}
