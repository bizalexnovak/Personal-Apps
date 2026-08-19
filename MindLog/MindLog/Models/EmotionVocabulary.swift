import Foundation

/// Word lists for the optional second step after a mood check-in — never a
/// replacement for the 1-5 scale, always an *optional* layer on top of it.
/// The number is still the entry's mood; a word is just colour, and skipping
/// the word grid entirely is a fully supported path (see MoodDetailStep).
enum EmotionVocabulary {

    /// Words grouped by the mood just tapped, so the grid shown next feels
    /// relevant rather than a flat alphabetical dump.
    private static let byMood: [Int: [String]] = [
        1: ["drained", "hopeless", "ashamed", "overwhelmed", "numb", "grieving"],
        2: ["anxious", "irritable", "lonely", "restless", "discouraged", "tense"],
        3: ["flat", "fine", "distracted", "tired", "steady", "unsure"],
        4: ["calm", "content", "focused", "connected", "hopeful", "grateful"],
        5: ["joyful", "energised", "proud", "loved", "playful", "at ease"],
    ]

    /// Words for a given mood, clamped to the 1-5 range so an out-of-range
    /// score (or one that's nil and defaulted upstream) still gets a list.
    static func words(for mood: Int) -> [String] {
        let clamped = min(5, max(1, mood))
        return byMood[clamped] ?? []
    }

    /// Every word across every mood, in mood order — used where a single
    /// entry has no mood at all and there's nothing to key off.
    static let all: [String] = (1...5).flatMap { byMood[$0] ?? [] }
}

/// Who/what/where context tags — the same optional, skippable second-step
/// idea as `EmotionVocabulary`, just for the situation rather than the
/// feeling. Never required, never scored.
enum ContextTagCatalog {

    static let groups: [(title: String, tags: [String])] = [
        ("Who", ["alone", "family", "friends", "partner", "colleagues"]),
        ("What", ["work", "rest", "exercise", "chores", "screens", "creating"]),
        ("Where", ["home", "out", "outside", "travel", "work"]),
    ]

    static let all: [String] = groups.flatMap { $0.tags }
}
