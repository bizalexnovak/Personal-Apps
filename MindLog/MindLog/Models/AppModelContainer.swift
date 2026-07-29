import Foundation
import SwiftData

/// Single ModelContainer shared across the app.
enum AppModelContainer {
    /// Single source of truth for the persisted model set — reused by the app
    /// container and by the in-memory containers the tests spin up.
    static let models: [any PersistentModel.Type] = [
        JournalEntry.self, ActivityLog.self,
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
