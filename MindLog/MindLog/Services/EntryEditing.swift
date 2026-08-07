import Foundation

/// Pure rules for re-dating and editing entries. The top complaint about the
/// competition is that you can't fix *when* something happened — so every
/// entry's timestamp is editable and an entry can be created for a past day.
/// The logic lives here (not in the view) so it can be unit-tested.
enum EntryEditing {
    /// How far back an entry may be dated. Long enough to backfill a trip you
    /// forgot to log, short enough that a fat-fingered year is caught.
    static let maximumBackdateDays = 365

    /// Combine a chosen day with a chosen time-of-day. Backdating is a
    /// two-part question — "which day" then "roughly when" — and picking a day
    /// shouldn't silently drag the time along with it.
    static func combine(
        day: Date, time: Date, calendar: Calendar = .current
    ) -> Date {
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute, .second], from: time)
        var parts = DateComponents()
        parts.year = dayParts.year
        parts.month = dayParts.month
        parts.day = dayParts.day
        parts.hour = timeParts.hour
        parts.minute = timeParts.minute
        parts.second = timeParts.second
        return calendar.date(from: parts) ?? day
    }

    /// The window a date picker may offer: from `maximumBackdateDays` ago up
    /// to now. Entries can't be dated into the future — a mood you haven't had
    /// yet isn't data.
    static func allowedRange(now: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date> {
        let earliest = calendar.date(byAdding: .day, value: -maximumBackdateDays, to: now) ?? now
        return earliest...now
    }

    /// Clamp an edited timestamp into the allowed window.
    static func clamp(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        let range = allowedRange(now: now, calendar: calendar)
        return min(max(date, range.lowerBound), range.upperBound)
    }

    /// Timestamp for an entry being created for an earlier day. Today keeps
    /// the current clock time; an earlier day lands at the same time of day,
    /// which reads far more honestly in the timeline than midnight.
    static func timestampForDay(
        _ day: Date, now: Date = .now, calendar: Calendar = .current
    ) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        return clamp(combine(day: day, time: now, calendar: calendar), now: now, calendar: calendar)
    }

    /// Human label for when an entry sits, used on the edit sheet so a
    /// backdated entry announces itself rather than quietly changing history.
    static func relativeDayLabel(
        for date: Date, now: Date = .now, calendar: Calendar = .current
    ) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Whether an edit actually changes anything — lets the edit sheet leave
    /// Save inert instead of rewriting a timestamp on every open.
    static func hasChanges(
        originalText: String, originalMood: Int?, originalTimestamp: Date,
        originalEmotionWords: [String], originalContextTags: [String],
        text: String, mood: Int?, timestamp: Date,
        emotionWords: [String], contextTags: [String]
    ) -> Bool {
        originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            != text.trimmingCharacters(in: .whitespacesAndNewlines)
            || originalMood != mood
            || abs(originalTimestamp.timeIntervalSince(timestamp)) >= 1
            || EmotionVocabulary.normalize(originalEmotionWords)
                != EmotionVocabulary.normalize(emotionWords)
            || EmotionVocabulary.normalize(originalContextTags)
                != EmotionVocabulary.normalize(contextTags)
    }
}
