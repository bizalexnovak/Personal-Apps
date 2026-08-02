import Foundation
import SwiftData

/// Single ModelContainer shared by the SwiftUI app and the App Intent.
/// LogMealIntent runs inside the app's process, so both surfaces must write
/// through the same container to see each other's data immediately.
enum AppModelContainer {
    /// Single source of truth for the persisted model set — reused by the app
    /// container and by the in-memory containers the tests spin up.
    static let models: [any PersistentModel.Type] = [
        Meal.self, FoodItem.self, RememberedMatch.self,
        Recipe.self, RecipeIngredient.self, CustomFood.self,
    ]

    static let shared: ModelContainer = {
        let schema = Schema(models)
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
