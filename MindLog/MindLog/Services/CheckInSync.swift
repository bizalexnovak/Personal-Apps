import Foundation
import SwiftData

/// Turns check-ins captured outside the app — a widget tap on the lock screen,
/// a notification action — into real `JournalEntry` rows.
///
/// The widget runs in its own process and a notification action runs in a
/// short-lived callback; neither can safely open the app's SwiftData store.
/// So both just append a `PendingCheckIn` to the App Group inbox, and the app
/// drains that inbox the next time it runs. The mood is captured the instant
/// it's tapped (that's the five-second promise); the row it becomes lands a
/// moment later, timestamped with the tap, not with the drain.
enum CheckInSync {

    /// Which pending check-ins still need to become rows. Pure so it can be
    /// tested without a store: dedupe is by id, which the sender chose, so
    /// draining twice — or draining a queue that was never cleared after a
    /// crash — can't double-log.
    static func unsynced(
        pending: [PendingCheckIn], existingIDs: Set<UUID>
    ) -> [PendingCheckIn] {
        var seen = existingIDs
        var result: [PendingCheckIn] = []
        for item in pending where !seen.contains(item.id) {
            seen.insert(item.id)
            result.append(item)
        }
        return result
    }

    /// The row a pending check-in becomes. Same model as every other entry, so
    /// the timeline stays one timeline.
    static func entry(for pending: PendingCheckIn) -> JournalEntry {
        JournalEntry(
            id: pending.id,
            timestamp: pending.timestamp,
            text: "",
            source: EntrySource.checkIn,
            moodScore: pending.moodScore.clampedToMood
        )
    }

    /// Today's picture for the widget, derived from the live rows.
    static func snapshot(
        from entries: [JournalEntry], on date: Date = .now, calendar: Calendar = .current
    ) -> CheckInSnapshot {
        let today = entries
            .filter { $0.moodScore != nil && calendar.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp < $1.timestamp }
        return CheckInSnapshot(
            day: calendar.startOfDay(for: date),
            latestMood: today.last?.moodScore,
            latestMoodAt: today.last?.timestamp,
            checkInCount: today.count
        )
    }

    /// Drains the inbox into the context. Returns the ids that became rows.
    @MainActor
    @discardableResult
    static func drain(into context: ModelContext, existing entries: [JournalEntry]) -> [UUID] {
        let queued = CheckInInbox.pending()
        guard !queued.isEmpty else { return [] }
        let toInsert = unsynced(pending: queued, existingIDs: Set(entries.map(\.id)))
        for item in toInsert {
            context.insert(entry(for: item))
        }
        // Everything queued is accounted for now — either just inserted or
        // already present — so the whole queue clears, not just the inserts.
        CheckInInbox.clear(ids: queued.map(\.id))
        return toInsert.map(\.id)
    }
}

extension Int {
    /// Anything arriving from another process gets pinned to the 1-5 scale
    /// before it becomes a row.
    var clampedToMood: Int {
        Swift.min(Mood.range.upperBound, Swift.max(Mood.range.lowerBound, self))
    }
}

/// The pure half of entry editing: moving an entry in time. Kept out of the
/// view so it can be tested, and so backdating behaves identically wherever
/// it's offered (the detail sheet, the "log for another day" path).
///
/// Top complaint about competing trackers is that a moment you forgot to log
/// is a moment you can never log. So: any entry's timestamp can be moved, to
/// any past instant, and a new entry can be created for an earlier day.
enum EntryEditing {

    /// The window an entry may be moved within: any time up to now, and no
    /// further back than a year — far enough for real backfill, near enough
    /// that a mis-scrolled year can't silently bury an entry.
    static let maximumBackdateDays = 365

    static func earliestAllowed(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -maximumBackdateDays, to: now) ?? now
    }

    /// Clamps a requested timestamp into the allowed window. Future dates snap
    /// back to now — you can log what happened, not what hasn't.
    static func clamp(_ requested: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        let earliest = earliestAllowed(now: now, calendar: calendar)
        if requested > now { return now }
        if requested < earliest { return earliest }
        return requested
    }

    /// The timestamp for an entry being created *for* a past day: keep the
    /// chosen day, keep the current time of day, so a backfilled entry sits
    /// somewhere plausible rather than at midnight.
    static func backdated(
        toDayOf day: Date, now: Date = .now, calendar: Calendar = .current
    ) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = time.hour
        comps.minute = time.minute
        comps.second = time.second
        let candidate = calendar.date(from: comps) ?? day
        return clamp(candidate, now: now, calendar: calendar)
    }

    /// True when moving this entry actually changes which day it belongs to —
    /// the case worth confirming, since it moves the entry between days in
    /// Trends and in the practice score.
    static func changesDay(
        from old: Date, to new: Date, calendar: Calendar = .current
    ) -> Bool {
        !calendar.isDate(old, inSameDayAs: new)
    }
}
