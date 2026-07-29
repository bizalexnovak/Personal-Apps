import Foundation

/// One calendar day, summarized for trends & insights. Built by the views
/// from SwiftData rows; kept as a value type so the engine is pure and the
/// tests never need a database.
struct DaySummary: Equatable {
    /// Start of day in the current calendar.
    var date: Date
    var score: Double
    /// Average of the day's recorded moods (1…5); nil if none recorded.
    var averageMood: Double?
    /// Which activities were logged at all that day.
    var activityIDs: Set<String>
    var journaled: Bool

    /// A day "counts" for streaks when anything at all was done.
    var isActive: Bool { score > 0 }
}

/// A ready-to-render insight card.
struct Insight: Identifiable, Equatable {
    var id: String
    var icon: String
    var title: String
    var detail: String
}

/// All-local analytics over the day summaries. Everything here is descriptive
/// ("your averages differ"), never diagnostic — and worded that way in the UI.
enum InsightsEngine {
    /// Days-with-mood required on BOTH sides before a comparison is shown;
    /// below this the "insight" would be noise.
    static let minimumSample = 3

    // MARK: - Streaks

    /// Consecutive active days ending today or yesterday (a streak isn't
    /// broken by a day that isn't over yet).
    static func currentStreak(
        days: [DaySummary], today: Date, calendar: Calendar = .current
    ) -> Int {
        let activeDays = Set(days.filter(\.isActive).map { calendar.startOfDay(for: $0.date) })
        var cursor = calendar.startOfDay(for: today)
        if !activeDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while activeDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    static func bestStreak(days: [DaySummary], calendar: Calendar = .current) -> Int {
        let activeDays = Set(days.filter(\.isActive).map { calendar.startOfDay(for: $0.date) })
        var best = 0
        for day in activeDays {
            // Only count from streak starts, so each run is measured once.
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day),
                  !activeDays.contains(previous) else { continue }
            var length = 0
            var cursor = day
            while activeDays.contains(cursor) {
                length += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            best = max(best, length)
        }
        return best
    }

    // MARK: - Mood relationships

    /// Average mood on days with the activity minus days without it.
    /// Positive ≈ "your mood runs higher on days you do this". nil until both
    /// sides have a real sample — never invented from thin data.
    static func moodLift(activityID: String, days: [DaySummary]) -> Double? {
        let rated = days.filter { $0.averageMood != nil }
        let with = rated.filter { $0.activityIDs.contains(activityID) }
        let without = rated.filter { !$0.activityIDs.contains(activityID) }
        guard with.count >= minimumSample, without.count >= minimumSample else { return nil }
        return average(with.compactMap(\.averageMood)) - average(without.compactMap(\.averageMood))
    }

    /// Same comparison for journaling itself.
    static func journalingMoodLift(days: [DaySummary]) -> Double? {
        let rated = days.filter { $0.averageMood != nil }
        let with = rated.filter(\.journaled)
        let without = rated.filter { !$0.journaled }
        guard with.count >= minimumSample, without.count >= minimumSample else { return nil }
        return average(with.compactMap(\.averageMood)) - average(without.compactMap(\.averageMood))
    }

    /// Average mood over the last 7 days minus the 7 before that (relative to
    /// `today`). nil until both weeks have at least one rated day.
    static func weeklyMoodDelta(
        days: [DaySummary], today: Date, calendar: Calendar = .current
    ) -> Double? {
        let end = calendar.startOfDay(for: today)
        guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: end),
              let twoWeeksAgo = calendar.date(byAdding: .day, value: -13, to: end)
        else { return nil }
        let lastWeek = days.filter { $0.date >= weekAgo && $0.date <= end }.compactMap(\.averageMood)
        let priorWeek = days.filter { $0.date >= twoWeeksAgo && $0.date < weekAgo }.compactMap(\.averageMood)
        guard !lastWeek.isEmpty, !priorWeek.isEmpty else { return nil }
        return average(lastWeek) - average(priorWeek)
    }

    // MARK: - Cards

    /// The insight cards for the Trends screen, best first.
    static func insights(
        days: [DaySummary], today: Date, calendar: Calendar = .current
    ) -> [Insight] {
        var cards: [Insight] = []

        let streak = currentStreak(days: days, today: today, calendar: calendar)
        if streak >= 2 {
            cards.append(Insight(
                id: "streak", icon: "flame.fill",
                title: "\(streak)-day streak",
                detail: "You've done something for your mind \(streak) days running. Keep the chain going."
            ))
        }

        // The activity with the largest positive mood lift.
        let lifts: [(WellbeingActivity, Double)] = ActivityCatalog.all.compactMap { activity in
            guard let lift = moodLift(activityID: activity.id, days: days) else { return nil }
            return (activity, lift)
        }
        if let best = lifts.filter({ $0.1 >= 0.3 }).max(by: { $0.1 < $1.1 }) {
            cards.append(Insight(
                id: "lift.\(best.0.id)", icon: best.0.icon,
                title: "\(best.0.name) days feel better",
                detail: String(
                    format: "On days with %@, your mood has averaged %.1f higher (out of 5).",
                    best.0.name.lowercased(), best.1
                )
            ))
        }

        if let journalLift = journalingMoodLift(days: days), journalLift >= 0.3 {
            cards.append(Insight(
                id: "lift.journal", icon: "text.book.closed",
                title: "Journaling days feel better",
                detail: String(
                    format: "Your mood has averaged %.1f higher on days you wrote something down.",
                    journalLift
                )
            ))
        }

        if let delta = weeklyMoodDelta(days: days, today: today, calendar: calendar),
           abs(delta) >= 0.2 {
            let up = delta > 0
            cards.append(Insight(
                id: "week", icon: up ? "arrow.up.right" : "arrow.down.right",
                title: up ? "Trending up" : "A heavier week",
                detail: up
                    ? String(format: "Your average mood is up %.1f versus the week before.", delta)
                    : String(format: "Your average mood is down %.1f versus the week before. Days like these are what the practices are for.", -delta)
            ))
        }

        return cards
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
