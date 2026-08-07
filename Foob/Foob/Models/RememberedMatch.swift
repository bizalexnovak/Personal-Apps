import Foundation
import SwiftData
import os

/// A learned correction: when the user searches/picks a different USDA food
/// for an item, we remember `phrase → that food` so the next time the same
/// phrase is logged we skip the (faulty) search and reuse the confirmed food.
@Model
final class RememberedMatch {
    // CloudKit rules — see the note on `Meal`. `phrase` used to be `.unique`;
    // `remember(phrase:...)` below already upserts by fetching first, and
    // `lookup` takes the newest row, so duplicates arriving from sync are
    // harmless and get collapsed on the next write.
    /// Normalized food name the user logged (lowercased, trimmed).
    var phrase: String = ""
    /// JSON-encoded USDAFood so we can re-scale it to whatever quantity/unit
    /// comes in next time, not just replay a fixed macro total.
    var foodJSON: Data = Data()
    /// Human-readable matched description, for diagnostics/logging.
    var matchedDescription: String = ""
    var updatedAt: Date = Date.distantPast

    init(phrase: String, foodJSON: Data, matchedDescription: String, updatedAt: Date = .now) {
        self.phrase = phrase
        self.foodJSON = foodJSON
        self.matchedDescription = matchedDescription
        self.updatedAt = updatedAt
    }
}

/// Read/write helpers for the remembered-correction table. Kept separate from
/// the model so the coordinator can call plain functions with its context.
enum RememberedMatchStore {
    private static let logger = Logger(subsystem: "com.alexnovak.foob", category: "remembered")

    /// Normalization is intentionally simple: case-fold and collapse spaces so
    /// "Celsius Energy Drink" and "celsius  energy drink" hit the same entry.
    static func normalize(_ phrase: String) -> String {
        phrase.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .joined(separator: " ")
    }

    static func lookup(phrase: String, in context: ModelContext) -> USDAFood? {
        let key = normalize(phrase)
        // Newest first: without a unique constraint, sync can briefly leave two
        // rows for the same phrase — the most recent correction wins.
        var descriptor = FetchDescriptor<RememberedMatch>(
            predicate: #Predicate { $0.phrase == key },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let row = try? context.fetch(descriptor).first else { return nil }
        guard let food = try? JSONDecoder().decode(USDAFood.self, from: row.foodJSON) else { return nil }
        logger.debug("remembered match for \"\(key, privacy: .public)\" → \(row.matchedDescription, privacy: .public)")
        return food
    }

    static func remember(phrase: String, food: USDAFood, in context: ModelContext) {
        let key = normalize(phrase)
        guard let data = try? JSONEncoder().encode(food) else { return }
        // Upsert: replace any existing mapping for this phrase.
        let existing = FetchDescriptor<RememberedMatch>(predicate: #Predicate { $0.phrase == key })
        let rows = (try? context.fetch(existing)) ?? []
        if let row = rows.first {
            row.foodJSON = data
            row.matchedDescription = food.description
            row.updatedAt = .now
            // Collapse any duplicates that arrived from another device.
            for extra in rows.dropFirst() { context.delete(extra) }
        } else {
            context.insert(RememberedMatch(phrase: key, foodJSON: data, matchedDescription: food.description))
        }
        try? context.save()
        logger.debug("remembered \"\(key, privacy: .public)\" → \(food.description, privacy: .public)")
    }
}
