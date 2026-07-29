import Foundation

/// The daily practice score (0–100): how much you *did* for your mind today.
/// Deliberately measures actions, not outcomes — a hard day where you still
/// meditated and journaled scores well, because that's the behaviour worth
/// reinforcing. Mood is tracked separately and the two are only related in
/// Trends ("on days you meditate, your mood averages higher").
enum PracticeScore {
    /// Everything the score needs about one calendar day, already aggregated.
    /// Value type so the math is trivially testable without SwiftData.
    struct DayInput: Equatable {
        /// Total minutes per activity id.
        var activityMinutes: [String: Double] = [:]
        /// Any journal entry with real text (voice or typed).
        var journaled = false
        /// Any mood recorded (check-in or attached to an entry).
        var checkedIn = false
    }

    /// Writing something down is worth a solid chunk on its own…
    static let journalBonus = 15.0
    /// …and the ten-second mood check-in earns a little, to build the habit.
    static let checkInBonus = 5.0
    static let maxScore = 100.0

    /// The default daily target (Settings → Daily goal). 50 ≈ one real
    /// practice + a journal entry: an intentionally reachable bar.
    static let defaultGoal = 50.0

    static func score(for input: DayInput) -> Double {
        var total = activityPoints(for: input.activityMinutes)
        if input.journaled { total += journalBonus }
        if input.checkedIn { total += checkInBonus }
        return min(maxScore, total)
    }

    /// Σ per-activity points, each capped at its daily max so variety beats
    /// grinding one thing. Multiple logs of the same activity share one cap.
    static func activityPoints(for minutesByID: [String: Double]) -> Double {
        minutesByID.reduce(0) { sum, pair in
            let activity = ActivityCatalog.activity(for: pair.key)
            let counted = min(max(pair.value, 0), activity.capMinutes)
            return sum + counted * activity.pointsPerMinute
        }
    }

    /// Aggregate a day's raw logs/entries into a `DayInput`.
    static func dayInput(entries: [JournalEntry], logs: [ActivityLog]) -> DayInput {
        var input = DayInput()
        for log in logs {
            input.activityMinutes[log.activityID, default: 0] += log.minutes
        }
        input.journaled = entries.contains { !$0.isCheckIn }
        input.checkedIn = entries.contains { $0.moodScore != nil }
        return input
    }
}
