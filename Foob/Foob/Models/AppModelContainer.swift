import Foundation
import SwiftData
import os

/// Single ModelContainer shared by the SwiftUI app and the App Intent.
/// LogMealIntent runs inside the app's process, so both surfaces must write
/// through the same container to see each other's data immediately.
///
/// The store is backed by the user's private CloudKit database, so everything
/// logged survives deleting and reinstalling the app. Sync is a silent
/// enhancement: with no iCloud account, iCloud Drive off, or no network, the
/// same local store keeps working and the app is fully usable. See
/// docs/ICLOUD.md for the model rules this imposes.
enum AppModelContainer {
    private static let logger = Logger(subsystem: "com.alexnovak.foob", category: "cloudkit")

    /// Must match the iCloud container in Foob.entitlements.
    static let cloudKitContainerID = "iCloud.com.alexnovak.Foob"

    /// Single source of truth for the persisted model set — reused by the app
    /// container and by the in-memory containers the tests spin up.
    static let models: [any PersistentModel.Type] = [
        Meal.self, FoodItem.self, RememberedMatch.self,
        Recipe.self, RecipeIngredient.self, CustomFood.self,
    ]

    /// How the shared store actually opened. `localOnly` means CloudKit could
    /// not be attached at all (missing entitlement, simulator without iCloud
    /// support, schema rejected) — the app still works, it just won't sync.
    /// Note this is about the STORE, not the account: a CloudKit-backed store
    /// opens fine when the user is signed out, it simply doesn't sync until
    /// they sign in. `CloudSyncStatus` reports that half.
    enum StoreMode {
        case cloudKit
        case localOnly(reason: String)
    }

    private(set) static var storeMode: StoreMode = .localOnly(reason: "Store not opened yet")

    static let shared: ModelContainer = {
        let schema = Schema(models)
        do {
            let config = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            storeMode = .cloudKit
            logger.info("model store opened with CloudKit private database")
            return container
        } catch {
            // Never fatal on the CloudKit path: a broken/absent iCloud setup
            // must not stop the app opening. Fall back to the same on-disk
            // store with sync switched off — no data is lost either way, and
            // it starts syncing again once the CloudKit path works.
            let reason = error.localizedDescription
            logger.error("CloudKit store failed (\(reason, privacy: .public)) — falling back to local-only")
            do {
                let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, configurations: [config])
                storeMode = .localOnly(reason: reason)
                return container
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }()
}
