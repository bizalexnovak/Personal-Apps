import Foundation

/// Everything the widget extension and the app both need. Deliberately plain
/// Foundation — no SwiftData, no SwiftUI — so the widget process never has to
/// load the app's model stack (same trick Foob's `DayNutritionSnapshot` uses).
///
/// Nothing here leaves the phone. The App Group is a second on-device sandbox
/// shared between two processes of the same app; it is not a server, not a
/// sync, and not an account. MindLog's covenant is unchanged.

// MARK: - Shared identifiers

enum MindLogSharing {
    /// Must match the `com.apple.security.application-groups` entry in BOTH
    /// MindLog.entitlements and MindLogWidget.entitlements. Change one, change all three.
    static let appGroup = "group.com.alexnovak.MindLog"

    static let widgetKind = "MindLogCheckInWidget"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }
}

/// Where a mood check-in was captured. The app writes the matching
/// `EntrySource` when it drains the queue, so the journal timeline can tell
/// the story of *how* a moment was caught without splitting the model.
enum CheckInOrigin: String, Codable, CaseIterable {
    case widget
    case notification
    case app
}

// MARK: - Pending check-ins

/// A mood tapped somewhere the SwiftData store isn't reachable — the widget
/// extension (a separate process) or a notification action (which runs in a
/// short-lived background callback). The app drains these into real
/// `JournalEntry` rows the next time it runs.
///
/// `id` is the eventual `JournalEntry.id`, which is what makes draining
/// idempotent: replaying the same queue twice can't double-log.
struct PendingCheckIn: Codable, Equatable, Identifiable {
    var id: UUID
    var moodScore: Int
    var timestamp: Date
    var origin: CheckInOrigin

    init(
        id: UUID = UUID(),
        moodScore: Int,
        timestamp: Date = .now,
        origin: CheckInOrigin
    ) {
        self.id = id
        self.moodScore = moodScore
        self.timestamp = timestamp
        self.origin = origin
    }
}

/// The hand-off queue in App Group storage. Small, append-only, drained by the
/// app. Kept as JSON in `UserDefaults` rather than a shared SwiftData store so
/// the existing on-device database never has to move (moving it would strand
/// every entry someone has already written).
enum CheckInInbox {
    private static let key = "mindlog_pending_checkins"
    /// A safety valve: if the app somehow never runs, the queue still can't grow
    /// without bound. Oldest are dropped first.
    static let capacity = 64

    static func pending() -> [PendingCheckIn] {
        guard let defaults = MindLogSharing.defaults,
              let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([PendingCheckIn].self, from: data)
        else { return [] }
        return items
    }

    /// Appends one check-in. Returns the full queue as it now stands.
    @discardableResult
    static func enqueue(_ item: PendingCheckIn) -> [PendingCheckIn] {
        let next = trimmed(pending() + [item])
        write(next)
        return next
    }

    /// Removes the given ids — called once the app has turned them into rows.
    static func clear(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let remove = Set(ids)
        write(pending().filter { !remove.contains($0.id) })
    }

    static func removeAll() { write([]) }

    static func trimmed(_ items: [PendingCheckIn]) -> [PendingCheckIn] {
        items.count <= capacity ? items : Array(items.suffix(capacity))
    }

    private static func write(_ items: [PendingCheckIn]) {
        guard let defaults = MindLogSharing.defaults,
              let data = try? JSONEncoder().encode(items)
        else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Widget snapshot

/// What the widget draws. Written by the app whenever today's picture changes,
/// and nudged optimistically by the widget's own intent so a tap looks
/// answered immediately instead of waiting for the app to next open.
struct CheckInSnapshot: Codable, Equatable {
    /// Start of the day this snapshot describes — used to blank it out at
    /// midnight without needing the app to run.
    var day: Date
    /// The most recent mood logged that day, if any.
    var latestMood: Int?
    /// When that mood was logged.
    var latestMoodAt: Date?
    /// How many check-ins that day — the widget shows a quiet count, never a
    /// streak or a target. This is not a score.
    var checkInCount: Int

    init(
        day: Date = Calendar.current.startOfDay(for: .now),
        latestMood: Int? = nil,
        latestMoodAt: Date? = nil,
        checkInCount: Int = 0
    ) {
        self.day = day
        self.latestMood = latestMood
        self.latestMoodAt = latestMoodAt
        self.checkInCount = checkInCount
    }

    static let empty = CheckInSnapshot()

    /// A snapshot from an earlier day says nothing about today, so it reads as
    /// empty rather than stale. Pure, so it's unit-testable.
    func resolved(for date: Date, calendar: Calendar = .current) -> CheckInSnapshot {
        calendar.isDate(day, inSameDayAs: date)
            ? self
            : CheckInSnapshot(day: calendar.startOfDay(for: date))
    }

    /// Folds a freshly tapped mood in, so the widget can redraw before the app
    /// has ever seen it.
    func adding(mood: Int, at date: Date, calendar: Calendar = .current) -> CheckInSnapshot {
        var next = resolved(for: date, calendar: calendar)
        next.latestMood = mood
        next.latestMoodAt = date
        next.checkInCount += 1
        return next
    }
}

enum CheckInSnapshotStore {
    private static let key = "mindlog_checkin_snapshot"

    static func read() -> CheckInSnapshot {
        guard let defaults = MindLogSharing.defaults,
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(CheckInSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    static func write(_ snapshot: CheckInSnapshot) {
        guard let defaults = MindLogSharing.defaults,
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: key)
    }
}
