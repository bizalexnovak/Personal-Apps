import Foundation

/// Rolls raw rows (journal entries + activity logs) up into per-day
/// summaries for Trends and the insights engine. Pure functions over value
/// snapshots so tests never need SwiftData.
enum DayAggregator {
    /// One summary per calendar day that has anything at all, sorted by date.
    static func summaries(
        entries: [JournalEntry], logs: [ActivityLog], calendar: Calendar = .current
    ) -> [DaySummary] {
        var entriesByDay: [Date: [JournalEntry]] = [:]
        for entry in entries {
            entriesByDay[calendar.startOfDay(for: entry.timestamp), default: []].append(entry)
        }
        var logsByDay: [Date: [ActivityLog]] = [:]
        for log in logs {
            logsByDay[calendar.startOfDay(for: log.timestamp), default: []].append(log)
        }

        let allDays = Set(entriesByDay.keys).union(logsByDay.keys)
        return allDays.sorted().map { day in
            summary(
                for: day,
                entries: entriesByDay[day] ?? [],
                logs: logsByDay[day] ?? []
            )
        }
    }

    /// Summary for one day whose rows are already filtered to that day.
    static func summary(for day: Date, entries: [JournalEntry], logs: [ActivityLog]) -> DaySummary {
        let input = PracticeScore.dayInput(entries: entries, logs: logs)
        let moods = entries.compactMap(\.moodScore)
        return DaySummary(
            date: day,
            score: PracticeScore.score(for: input),
            averageMood: moods.isEmpty ? nil : Double(moods.reduce(0, +)) / Double(moods.count),
            activityIDs: Set(logs.map(\.activityID)),
            journaled: input.journaled
        )
    }
}
