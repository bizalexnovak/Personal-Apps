import Foundation
import SwiftData

/// Nutrition lookup + persistence for already-resolved items. Parsing happens
/// upstream (MealCaptureCoordinator handles clarification between the two).
struct MealLoggingService {
    var parser: MealParsing = ClaudeMealParsingService()
    var nutrition: NutritionLookup = USDANutritionLookupService()

    /// One-shot pipeline without a clarification stage. Used by tests and any
    /// caller that has no UI to ask follow-ups.
    @MainActor
    @discardableResult
    func logMeal(from text: String, in context: ModelContext) async throws -> Meal {
        MatchDebugLog.shared.record(transcript: text)
        let requests = try await parser.parse(text)
        return try await save(requests: requests, rawText: text, in: context)
    }

    /// Saves items whose macros are already known — the coordinator's path,
    /// after each item was either looked up successfully or resolved manually.
    /// This never writes zeroed placeholders.
    @MainActor
    @discardableResult
    func saveResolved(
        _ entries: [(request: FoodItemRequest, match: NutritionMatch)],
        rawText: String,
        on date: Date = .now,
        in context: ModelContext
    ) throws -> Meal {
        let items = entries.map { request, match -> FoodItem in
            let item = FoodItem(
                name: request.name,
                quantity: request.quantity,
                unit: request.unit,
                calories: match.calories,
                protein: match.protein,
                carbs: match.carbs,
                fat: match.fat,
                matchConfidence: match.confidence
            )
            item.micros = match.micros
            return item
        }
        let meal = Meal(timestamp: date, rawText: rawText, items: items)
        context.insert(meal)
        try context.save()
        return meal
    }

    /// Looks up and saves resolved items. Nutrition lookups fail soft: an item
    /// whose lookup errors is still saved with zeroed macros and a "low"
    /// confidence flag so the user can fix it in the edit screen.
    /// Headless path only (tests / no-UI callers) — the app flow goes through
    /// MealCaptureCoordinator, which uses saveResolved and never zeroes.
    @MainActor
    @discardableResult
    func save(requests: [FoodItemRequest], rawText: String, in context: ModelContext) async throws -> Meal {
        var items: [FoodItem] = []
        for request in requests {
            let item = FoodItem(name: request.name, quantity: request.quantity, unit: request.unit)
            if let match = try? await nutrition.lookup(request) {
                item.calories = match.calories
                item.protein = match.protein
                item.carbs = match.carbs
                item.fat = match.fat
                item.matchConfidence = match.confidence
                item.micros = match.micros
            }
            items.append(item)
        }

        let meal = Meal(rawText: rawText, items: items)
        context.insert(meal)
        try context.save()
        return meal
    }
}
