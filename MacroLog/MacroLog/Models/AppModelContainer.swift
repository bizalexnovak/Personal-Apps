import Foundation
import SwiftData

/// Single ModelContainer shared by the SwiftUI app and the App Intent.
/// LogMealIntent runs inside the app's process, so both surfaces must write
/// through the same container to see each other's data immediately.
enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([Meal.self, FoodItem.self])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
