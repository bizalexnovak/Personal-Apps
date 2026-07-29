import Foundation
import NaturalLanguage

/// On-device sentiment for journal text via Apple's NaturalLanguage framework.
/// Nothing leaves the phone. The score is stored on the entry and used only as
/// a soft signal (a Trends overlay and a gentle hint on the review screen) —
/// the user's own 1–5 mood always outranks it.
enum SentimentAnalyzer {
    /// Average paragraph sentiment of `text`, -1 (negative) … 1 (positive).
    /// nil for empty/whitespace text or when the tagger has no opinion
    /// (very short fragments, unsupported languages).
    static func score(for text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = trimmed

        var scores: [Double] = []
        tagger.enumerateTags(
            in: trimmed.startIndex..<trimmed.endIndex,
            unit: .paragraph,
            scheme: .sentimentScore,
            options: [.omitWhitespace]
        ) { tag, _ in
            if let raw = tag?.rawValue, let value = Double(raw) {
                scores.append(value)
            }
            return true
        }
        guard !scores.isEmpty else { return nil }
        let mean = scores.reduce(0, +) / Double(scores.count)
        return min(1, max(-1, mean))
    }

    /// Map a sentiment score onto the 1–5 mood scale, for the review screen's
    /// "sounds like a ~Good day" hint. Pure, so the mapping is testable.
    static func moodEstimate(for score: Double) -> Int {
        switch score {
        case ..<(-0.6): return 1
        case ..<(-0.2): return 2
        case ..<0.2: return 3
        case ..<0.6: return 4
        default: return 5
        }
    }

    /// Soft wording for the hint chip — deliberately tentative.
    static func hint(for score: Double) -> String {
        "Sounds like a \(Mood.label(for: moodEstimate(for: score)).lowercased()) one"
    }
}
