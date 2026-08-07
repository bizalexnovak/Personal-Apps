import Foundation
import SwiftData

/// The one place a mood check-in becomes a `JournalEntry`, whatever door it
/// came through: the Today card, a lock-screen/home-screen widget button, or a
/// notification action. Keeping it in one function is what lets a check-in be
/// logged in under five seconds from anywhere without the app opening — the
/// widget extension and the notification handler compile this same file and
/// write into the App Group store (see `AppModelContainer.appGroupID`).
enum CheckInWriter {
    /// Build the entry for a check-in. Pure — no context, no side effects — so
    /// the creation rules are unit-testable without a store.
    static func makeEntry(
        mood: Int,
        at timestamp: Date = .now,
        emotionWords: [String] = [],
        contextTags: [String] = []
    ) -> JournalEntry {
        JournalEntry(
            timestamp: timestamp,
            text: "",
            source: EntrySource.checkIn,
            moodScore: clampedMood(mood),
            emotionWords: EmotionVocabulary.normalize(emotionWords),
            contextTags: EmotionVocabulary.normalize(contextTags)
        )
    }

    /// Insert a check-in into a context and return it (so a caller that wants
    /// to offer the optional second step has the entry to hand).
    @discardableResult
    static func log(
        mood: Int,
        at timestamp: Date = .now,
        into context: ModelContext
    ) -> JournalEntry {
        let entry = makeEntry(mood: mood, at: timestamp)
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// Log from outside the app process (widget intent, notification action),
    /// where there's no injected context to borrow. Returns false if the
    /// shared store couldn't be opened rather than trapping in an extension.
    @discardableResult
    static func logInSharedStore(mood: Int, at timestamp: Date = .now) -> Bool {
        guard let container = try? ModelContainer(
            for: Schema(AppModelContainer.models),
            configurations: [sharedConfiguration()]
        ) else { return false }
        let context = ModelContext(container)
        context.insert(makeEntry(mood: mood, at: timestamp))
        return (try? context.save()) != nil
    }

    private static func sharedConfiguration() -> ModelConfiguration {
        let schema = Schema(AppModelContainer.models)
        if let url = AppModelContainer.storeURL {
            return ModelConfiguration(schema: schema, url: url)
        }
        return ModelConfiguration(schema: schema)
    }

    /// A mood arriving from a widget or a notification action is still just an
    /// integer; keep it inside the 1…5 scale everything else assumes.
    static func clampedMood(_ mood: Int) -> Int {
        min(Mood.range.upperBound, max(Mood.range.lowerBound, mood))
    }
}
