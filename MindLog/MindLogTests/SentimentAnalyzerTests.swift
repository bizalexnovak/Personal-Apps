import XCTest
@testable import MindLog

final class SentimentAnalyzerTests: XCTestCase {
    func testEmptyTextHasNoScore() {
        XCTAssertNil(SentimentAnalyzer.score(for: ""))
        XCTAssertNil(SentimentAnalyzer.score(for: "   \n  "))
    }

    func testScoresStayInRange() {
        let texts = [
            "Today was wonderful. I felt calm and grateful all afternoon.",
            "Everything went wrong and I feel terrible about all of it.",
            "I bought groceries and did the laundry.",
        ]
        for text in texts {
            if let score = SentimentAnalyzer.score(for: text) {
                XCTAssertGreaterThanOrEqual(score, -1, text)
                XCTAssertLessThanOrEqual(score, 1, text)
            }
        }
    }

    func testPositiveTextScoresAboveNegativeText() throws {
        // NL sentiment models evolve, so assert ordering rather than values.
        // Skip (not fail) if the model has no opinion on either text — some
        // simulator environments lack the sentiment assets.
        let positive = SentimentAnalyzer.score(
            for: "Today was genuinely wonderful. I laughed a lot, felt calm, and I'm proud of what I did."
        )
        let negative = SentimentAnalyzer.score(
            for: "Today was awful. I felt anxious and miserable the whole time and everything went wrong."
        )
        guard let positive, let negative else {
            throw XCTSkip("Sentiment model unavailable in this environment")
        }
        XCTAssertGreaterThan(positive, negative)
    }

    // The score→mood mapping is pure and must stay stable — the review hint
    // and the Trends overlay both key off it.
    func testMoodEstimateMapping() {
        XCTAssertEqual(SentimentAnalyzer.moodEstimate(for: -1.0), 1)
        XCTAssertEqual(SentimentAnalyzer.moodEstimate(for: -0.7), 1)
        XCTAssertEqual(SentimentAnalyzer.moodEstimate(for: -0.4), 2)
        XCTAssertEqual(SentimentAnalyzer.moodEstimate(for: 0.0), 3)
        XCTAssertEqual(SentimentAnalyzer.moodEstimate(for: 0.4), 4)
        XCTAssertEqual(SentimentAnalyzer.moodEstimate(for: 0.8), 5)
        XCTAssertEqual(SentimentAnalyzer.moodEstimate(for: 1.0), 5)
    }

    func testHintWordsMatchTheMoodScale() {
        XCTAssertEqual(SentimentAnalyzer.hint(for: 0.8), "Sounds like a great one")
        XCTAssertEqual(SentimentAnalyzer.hint(for: -0.8), "Sounds like a rough one")
    }
}

final class JournalEntryTests: XCTestCase {
    func testCheckInDetection() {
        let checkIn = JournalEntry(source: EntrySource.checkIn, moodScore: 4)
        let written = JournalEntry(text: "Long day.", source: EntrySource.voice)
        let whitespaceOnly = JournalEntry(text: "  \n ", source: EntrySource.typed)
        XCTAssertTrue(checkIn.isCheckIn)
        XCTAssertFalse(written.isCheckIn)
        XCTAssertTrue(whitespaceOnly.isCheckIn)
    }

    func testSnippetTakesFirstNonEmptyLine() {
        let entry = JournalEntry(text: "\n\nFirst real line here.\nSecond line.")
        XCTAssertEqual(entry.snippet, "First real line here.")
    }

    func testSnippetTruncatesLongLines() {
        let long = String(repeating: "a", count: 200)
        let entry = JournalEntry(text: long)
        XCTAssertTrue(entry.snippet.hasSuffix("…"))
        XCTAssertLessThan(entry.snippet.count, 100)
    }

    func testMoodScaleCopy() {
        XCTAssertEqual(Mood.label(for: 1), "Rough")
        XCTAssertEqual(Mood.label(for: 3), "Okay")
        XCTAssertEqual(Mood.label(for: 5), "Great")
        XCTAssertEqual(Mood.emoji(for: 1), "😞")
        XCTAssertEqual(Mood.emoji(for: 5), "😄")
        // Out-of-range values clamp instead of crashing.
        XCTAssertEqual(Mood.label(for: 0), "Rough")
        XCTAssertEqual(Mood.label(for: 9), "Great")
    }
}
