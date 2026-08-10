import CloudKit
import Foundation
import Observation
import os

/// Read-only view of whether iCloud sync is actually happening, for the one
/// status row in Settings. Nothing in the app gates on this — it exists so the
/// user can tell at a glance whether their data is backed up, and why not if
/// it isn't. There is deliberately no sign-in UI: the device's iCloud account
/// is the identity, and being signed out is a supported state.
@Observable
@MainActor
final class CloudSyncStatus {
    static let shared = CloudSyncStatus()

    enum State: Equatable {
        /// Store is CloudKit-backed and the device is signed into iCloud.
        case on
        /// Everything works, it just isn't syncing. `reason` is user-facing.
        case off(reason: String)
        /// Haven't asked CloudKit yet.
        case unknown
    }

    private(set) var state: State = .unknown

    private let logger = Logger(subsystem: "com.alexnovak.foob", category: "cloudkit")

    private init() {}

    /// One line for the Settings row.
    var summary: String {
        switch state {
        case .on: return "On"
        case .off(let reason): return "Off — \(reason)"
        case .unknown: return "Checking…"
        }
    }

    var isOn: Bool { state == .on }

    /// Ask CloudKit where we stand. Safe to call repeatedly (Settings appearing,
    /// account change notifications); it never throws and never blocks the UI.
    func refresh() async {
        if case .localOnly(let reason) = AppModelContainer.storeMode {
            state = .off(reason: "this build couldn't attach to iCloud (\(reason))")
            return
        }

        let status: CKAccountStatus
        do {
            status = try await CKContainer(identifier: AppModelContainer.cloudKitContainerID).accountStatus()
        } catch {
            logger.error("accountStatus failed: \(error.localizedDescription, privacy: .public)")
            state = .off(reason: "couldn't reach iCloud right now")
            return
        }

        switch status {
        case .available:
            state = .on
        case .noAccount:
            state = .off(reason: "no iCloud account on this iPhone")
        case .restricted:
            state = .off(reason: "iCloud is restricted on this iPhone")
        case .couldNotDetermine:
            state = .off(reason: "couldn't reach iCloud right now")
        case .temporarilyUnavailable:
            state = .off(reason: "iCloud is temporarily unavailable")
        @unknown default:
            state = .off(reason: "iCloud is unavailable")
        }
        logger.debug("cloud sync status: \(self.summary, privacy: .public)")
    }
}
