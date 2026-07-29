import Foundation
import SwiftData

/// The app's own nutrition database: lookup, dedup, scan capture, and CSV
/// import over the `CustomFood` table. Searched BEFORE the USDA API in the
/// match pipeline — instant, offline, and it grows with every scan, upload,
/// and community sync.
enum CustomFoodStore {
    // MARK: - Dedup key

    /// Normalized name+brand: lowercase, alphanumerics collapsed, tokens
    /// sorted so word order doesn't create duplicates ("corona extra beer" ==
    /// "beer corona extra").
    static func nameKey(name: String, brand: String) -> String {
        let tokens = NameTokens.tokens(name) + NameTokens.tokens(brand)
        return Set(tokens).sorted().joined(separator: " ")
    }

    // MARK: - Matching

    /// Best match for a parsed item, or nil when nothing scores high enough.
    /// Requires ALL of the request's tokens to appear in the food's name+brand
    /// (partial overlap gives wrong foods a foothold; USDA handles the fuzzy
    /// long tail better).
    static func match(for request: FoodItemRequest, in context: ModelContext) -> NutritionMatch? {
        guard let food = bestRow(for: request.name, in: context) else { return nil }

        // Label values are per serving. Countable units scale by quantity
        // ("two Coronas"); weight/volume requests keep one serving — the
        // portion slider on the review card handles finer adjustment.
        let servings = countableUnits.contains(NameTokens.normalizedUnit(request.unit))
            ? max(request.quantity, 1)
            : 1
        let micros = food.microsData.flatMap { try? JSONDecoder().decode(Micronutrients.self, from: $0) } ?? .empty
        return NutritionMatch(
            matchedDescription: "\(food.displayName) · \(food.serving)",
            calories: food.calories * servings,
            protein: food.protein * servings,
            carbs: food.carbs * servings,
            fat: food.fat * servings,
            confidence: MatchConfidence.high, // printed label / published values
            micros: micros.scaled(by: servings)
        )
    }

    /// Units that mean "N servings of this item" (shared with the Open Food
    /// Facts lookup, which is also serving-based).
    static let countableUnits: Set<String> = [
        "serving", "servings", "can", "cans", "bottle", "bottles",
        "glass", "glasses", "slice", "slices", "piece", "pieces",
        "bar", "bars", "packet", "packets", "scoop", "scoops",
        "shot", "shots", "drink", "drinks", "sandwich", "sandwiches",
        "burger", "burgers", "taco", "tacos", "nugget", "nuggets",
        "order", "orders", "item", "items", "each", "cocktail", "cocktails",
    ]

    /// The best-scoring row whose name+brand contains EVERY token of the
    /// query. Among qualifiers, fewer extra tokens wins (tightest match).
    static func bestRow(for query: String, in context: ModelContext) -> CustomFood? {
        let queryTokens = Set(NameTokens.tokens(query))
        guard !queryTokens.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<CustomFood>())) ?? []
        var best: (food: CustomFood, extras: Int)?
        for food in all {
            let foodTokens = Set(NameTokens.tokens(food.name) + NameTokens.tokens(food.brand))
            guard queryTokens.isSubset(of: foodTokens) else { continue }
            let extras = foodTokens.count - queryTokens.count
            if best == nil || extras < best!.extras {
                best = (food, extras)
            }
        }
        return best?.food
    }

    /// Substring search for the browse UI (name, brand, or serving).
    static func search(_ query: String, in context: ModelContext) -> [CustomFood] {
        let all = (try? context.fetch(
            FetchDescriptor<CustomFood>(sortBy: [SortDescriptor(\.name)])
        )) ?? []
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.brand.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: - Adding rows

    /// Insert unless a row with the same normalized key exists. Returns true
    /// when a new row was added.
    @discardableResult
    static func addIfNew(_ food: CustomFood, in context: ModelContext) -> Bool {
        let key = food.nameKey
        var descriptor = FetchDescriptor<CustomFood>(predicate: #Predicate { $0.nameKey == key })
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) != nil { return false }
        context.insert(food)
        return true
    }

    /// Auto-capture from a label scan: every scanned label becomes a database
    /// row (deduped), so the next time anyone types or says the product name
    /// it matches instantly — even offline.
    static func addFromScan(name: String, label: LabelNutrition, in context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let micros = label.micronutrients
        let food = CustomFood(
            name: trimmed,
            serving: label.servingSize.isEmpty ? "1 serving" : label.servingSize,
            calories: label.calories,
            protein: label.protein,
            carbs: label.carbs,
            fat: label.fat,
            microsData: micros.isEmpty ? nil : try? JSONEncoder().encode(micros),
            source: "scan"
        )
        if addIfNew(food, in: context) {
            try? context.save()
            CommunitySync.pushSoon(context: context)
        }
    }

    // MARK: - CSV import

    /// Import a nutrition sheet. Expected header (case-insensitive):
    ///   name,brand,serving,calories,protein,carbs,fat[,<micro label>…]
    /// Extra columns are matched against `Micronutrients.fields` labels
    /// (e.g. "caffeine", "sodium", "added sugars"). Returns (added, skipped).
    static func importCSV(_ text: String, in context: ModelContext) throws -> (added: Int, skipped: Int) {
        var rows = parseCSV(text)
        guard rows.count >= 2 else { throw ImportError.empty }
        let header = rows.removeFirst().map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard let nameCol = header.firstIndex(of: "name"),
              let calCol = header.firstIndex(of: "calories") else {
            throw ImportError.badHeader
        }
        let col: (String) -> Int? = { header.firstIndex(of: $0) }
        // Extra columns → micronutrient fields, matched by (lowercased) label
        // with the parenthetical dropped: "thiamin (b1)" imports as "thiamin".
        let microColumns: [(index: Int, field: MicronutrientField)] = Micronutrients.fields.compactMap { field in
            let full = field.label.lowercased()
            let short = full.components(separatedBy: " (").first ?? full
            guard let index = header.firstIndex(of: full) ?? header.firstIndex(of: short) else { return nil }
            return (index, field)
        }

        func value(_ row: [String], _ index: Int?) -> Double {
            guard let index, index < row.count else { return 0 }
            return Double(row[index].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        func text(_ row: [String], _ index: Int?) -> String {
            guard let index, index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespaces)
        }

        var added = 0, skipped = 0
        for row in rows {
            let name = text(row, nameCol)
            guard !name.isEmpty else { continue }
            var micros = Micronutrients()
            for (index, field) in microColumns where index < row.count {
                if let v = Double(row[index].trimmingCharacters(in: .whitespaces)) {
                    micros[keyPath: field.keyPath] = v
                }
            }
            let serving = text(row, col("serving"))
            let food = CustomFood(
                name: name,
                brand: text(row, col("brand")),
                serving: serving.isEmpty ? "1 serving" : serving,
                calories: value(row, calCol),
                protein: value(row, col("protein")),
                carbs: value(row, col("carbs")),
                fat: value(row, col("fat")),
                microsData: micros.isEmpty ? nil : try? JSONEncoder().encode(micros),
                source: "import"
            )
            if addIfNew(food, in: context) { added += 1 } else { skipped += 1 }
        }
        try? context.save()
        if added > 0 { CommunitySync.pushSoon(context: context) }
        return (added, skipped)
    }

    enum ImportError: LocalizedError {
        case empty, badHeader
        var errorDescription: String? {
            switch self {
            case .empty: return "That file has no data rows."
            case .badHeader: return "The first row must be a header including at least \u{201C}name\u{201D} and \u{201C}calories\u{201D}."
            }
        }
    }

    /// Minimal CSV parser: commas, quoted fields with "" escapes, CRLF/LF.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else { inQuotes = false }
                } else { field.append(ch) }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",": endField()
                case "\n": endRow()
                case "\r": break
                default: field.append(ch)
                }
            }
        }
        endRow()
        return rows
    }
}
