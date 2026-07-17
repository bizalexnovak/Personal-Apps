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

    /// A fresh diary entry (timestamped now) built from this recipe.
    func makeMeal() -> Meal {
        let items = ingredients.map { ingredient in
            let item = FoodItem(
                name: ingredient.name, quantity: ingredient.quantity, unit: ingredient.unit,
                calories: ingredient.calories, protein: ingredient.protein,
                carbs: ingredient.carbs, fat: ingredient.fat,
                matchConfidence: MatchConfidence.high
            )
            item.microsData = ingredient.microsData
            return item
        }
        return Meal(timestamp: .now, rawText: name, items: items)
    }

    /// A recipe captured from an already-logged meal (its items as they are).
    static func from(meal: Meal, named name: String) -> Recipe {
        let ingredients = meal.items.map { item in
            RecipeIngredient(
                name: item.name, quantity: item.quantity, unit: item.unit,
                calories: item.calories, protein: item.protein,
                carbs: item.carbs, fat: item.fat,
                microsData: item.microsData
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
    /// Micronutrients JSON, same encoding as `FoodItem.microsData`.
    var microsData: Data?
    var recipe: Recipe?

    init(
        name: String,
        quantity: Double = 1,
        unit: String = "serving",
        calories: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        microsData: Data? = nil
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.microsData = microsData
    }
}
