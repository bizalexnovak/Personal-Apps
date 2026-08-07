import Foundation

/// The optional second step after a mood: a small grid of emotion words for
/// granularity beyond 1–5, and who/what/where tags for context. Both are
/// layers *on top of* the mood scale, never a replacement, and skipping them
/// takes zero taps — the check-in is already saved before this appears.
enum EmotionVocabulary {
    /// Emotion words grouped by which end of the 1–5 scale they usually sit
    /// at, so the grid can lead with the words that fit the mood just tapped
    /// without ever hiding the rest.
    struct Family: Identifiable {
        var id: String { name }
        var name: String
        /// Moods this family is offered first for.
        var moods: Set<Int>
        var words: [String]
    }

    static let families: [Family] = [
        Family(name: "Heavy", moods: [1, 2], words: [
            "drained", "anxious", "overwhelmed", "sad", "angry",
            "lonely", "ashamed", "numb", "irritable", "afraid",
        ]),
        Family(name: "Level", moods: [2, 3, 4], words: [
            "tired", "restless", "distracted", "okay", "steady",
            "quiet", "bored", "focused", "relieved", "hopeful",
        ]),
        Family(name: "Light", moods: [4, 5], words: [
            "content", "grateful", "proud", "energised", "connected",
            "playful", "calm", "excited", "loved", "clear",
        ]),
    ]

    /// The words to show first for a given mood, then everything else — so a
    /// mis-tap on the mood scale never buries the word someone wanted.
    static func words(forMood mood: Int) -> [String] {
        let clamped = CheckInWriter.clampedMood(mood)
        let leading = families.filter { $0.moods.contains(clamped) }.flatMap(\.words)
        let rest = families.filter { !$0.moods.contains(clamped) }.flatMap(\.words)
        return leading + rest
    }

    static let allWords: [String] = families.flatMap(\.words)

    /// Who / what / where, in that order — the three questions people actually
    /// answer when they ask themselves why a day went the way it did.
    static let contextTags: [String] = [
        "alone", "family", "friends", "partner", "coworkers", "strangers",
        "work", "school", "chores", "exercise", "rest", "screens",
        "home", "outside", "commute", "travel",
    ]

    /// Lower-cases, trims, drops blanks and de-duplicates while keeping the
    /// order the user tapped in. Applied on every write so stored tags stay
    /// comparable no matter which door the check-in came through.
    static func normalize(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { continue }
            result.append(cleaned)
        }
        return result
    }

    /// Toggle a word in a selection, preserving tap order.
    static func toggle(_ value: String, in selection: [String]) -> [String] {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return selection }
        var next = normalize(selection)
        if let index = next.firstIndex(of: cleaned) {
            next.remove(at: index)
        } else {
            next.append(cleaned)
        }
        return next
    }
}
