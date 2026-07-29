import Foundation
import SwiftData

/// One diary moment. Three shapes share the model so the journal reads as a
/// single timeline: a spoken entry (source "voice"), a typed entry ("typed"),
/// and a bare mood check-in ("checkin", empty text, mood only).
@Model
final class JournalEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var text: String
    /// How the entry was made: EntrySource.voice / .typed / .checkIn.
    var source: String
    /// Self-reported mood, 1 (rough) … 5 (great). Optional — attaching a mood
    /// to a written entry is encouraged, never required.
    var moodScore: Int?
    /// On-device sentiment of `text` (-1…1, Apple NaturalLanguage), computed
    /// once at save. nil for check-ins and whenever analysis was unavailable.
    /// Never shown as a judgement — it only feeds the Trends overlay.
    var sentimentScore: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        text: String = "",
        source: String = EntrySource.typed,
        moodScore: Int? = nil,
        sentimentScore: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.source = source
        self.moodScore = moodScore
        self.sentimentScore = sentimentScore
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mood-only check-ins have no prose to show; lists render the mood chip.
    var isCheckIn: Bool { trimmedText.isEmpty }

    /// First line, shortened, for timeline rows.
    var snippet: String {
        let firstLine = trimmedText
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        if firstLine.count <= 90 { return firstLine }
        return String(firstLine.prefix(90)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

enum EntrySource {
    static let voice = "voice"
    static let typed = "typed"
    static let checkIn = "checkin"
}

/// The five-step mood scale used everywhere a mood appears: check-ins, entry
/// review, the Today card, and the Trends chart axis.
enum Mood {
    static let range = 1...5

    static func emoji(for score: Int) -> String {
        switch score {
        case ...1: return "😞"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        default: return "😄"
        }
    }

    static func label(for score: Int) -> String {
        switch score {
        case ...1: return "Rough"
        case 2: return "Low"
        case 3: return "Okay"
        case 4: return "Good"
        default: return "Great"
        }
    }
}
