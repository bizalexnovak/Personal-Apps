import Foundation
import SwiftData

/// Orchestrates the full pipeline: raw text → Claude parse → USDA lookup →
/// saved Meal. Used by both the Siri intent and the in-app logging UI.
struct MealLoggingService {
    var parser: MealParsing = ClaudeMealParsingService()
    var nutrition: NutritionLookup = USDANutritionLookupService()

    /// Parses, looks up, and saves a meal. Nutrition lookups fail soft: an
    /// item whose lookup errors is still saved with zeroed macros and a "low"
    /// confidence flag so the user can fix it in the edit screen.
    @MainActor
    @discardableResult
    func logMeal(from text: String, in context: ModelContext) async throws -> Meal {
        let requests = try await parser.parse(text)

        var items: [FoodItem] = []
        for request in requests {
            let item = FoodItem(name: request.name, quantity: request.quantity, unit: request.unit)
            if let match = try? await nutrition.lookup(request) {
                item.calories = match.calories
                item.protein = match.protein
                item.carbs = match.carbs
                item.fat = match.fat
                item.matchConfidence = match.confidence
            }
            items.append(item)
        }

        let meal = Meal(rawText: text, items: items)
        context.insert(meal)
        try context.save()
        return meal
    }
}
