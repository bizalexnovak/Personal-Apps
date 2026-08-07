import Foundation
import SwiftData

/// Single ModelContainer shared across the app.
enum AppModelContainer {
    /// Single source of truth for the persisted model set — reused by the app
    /// container and by the in-memory containers the tests spin up.
    static let models: [any PersistentModel.Type] = [
        JournalEntry.self, ActivityLog.self,
    ]

    /// App Group shared by the app and the widget extension. The store lives
    /// here (not in the app's own container) so a widget/notification check-in
    /// writes into the very same journal the app reads — still entirely on
    /// this device, no account and no server.
    static let appGroupID = "group.com.alexnovak.MindLog"

    /// Where the SwiftData store file lives. Falls back to the target's own
    /// default location if the App Group isn't available (e.g. a simulator
    /// build before the capability is enabled), so the app still runs.
    static var storeURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: "MindLog.store")
    }

    static let shared: ModelContainer = {
        let schema = Schema(models)
        let configuration = storeURL.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
