import Foundation

protocol MealParsing {
    /// Turns free-form meal text ("2 eggs and a slice of toast") into structured items.
    func parse(_ mealText: String) async throws -> [FoodItemRequest]
}

enum MealParsingError: LocalizedError {
    case missingAPIKey
    case httpError(status: Int, body: String)
    case emptyResponse
    case invalidJSON(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Claude API key is set. Add one in Settings."
        case .httpError(let status, _):
            return "The Claude API returned an error (HTTP \(status))."
        case .emptyResponse:
            return "The Claude API returned an empty response."
        case .invalidJSON:
            return "Couldn't understand the meal description. Try rephrasing it."
        }
    }
}

/// Sends raw meal text to Anthropic's Messages API and parses the JSON reply.
struct ClaudeMealParsingService: MealParsing {
    static let systemPrompt = """
    You are a nutrition parsing assistant. Given a description of a meal, extract each distinct food item with its estimated quantity and unit. Respond ONLY with valid JSON, no markdown formatting, no preamble.
    Format: {"items": [{"name": string, "quantity": number, "unit": string, "calories": number or null, "protein": number or null, "carbs": number or null, "fat": number or null, "needsClarification": boolean, "clarificationQuestion": string or null, "options": [{"label": string, "name": string, "quantity": number, "unit": string}] or null}]}
    If the user states specific nutrition numbers for an item — calories (kcal) or protein/carbs/fat (grams) — put them in the matching field for THAT item and set needsClarification false (you already have the numbers). Example: "chicken, 64 grams of protein, 60 grams of carbs, 25 grams of fat" -> {"name": "chicken", "quantity": 1, "unit": "serving", "calories": null, "protein": 64, "carbs": 60, "fat": 25}. If the user gives no numbers for an item, set calories/protein/carbs/fat to null.
    CRITICAL — the "name" field must contain ONLY the clean food or product name, never the user's sentence. Strip out first-person phrasing ("I ate", "I drank", "I had"), verbs, articles, quantities, and container words — those belong in "quantity" and "unit", not "name". The name should read like a label on a shelf: a few words at most.
    Examples:
    - "I drank one can of celsius" -> {"name": "Celsius energy drink", "quantity": 1, "unit": "can"}
    - "had two scrambled eggs and a slice of sourdough toast" -> two items: {"name": "scrambled eggs", "quantity": 2, "unit": "large"} and {"name": "sourdough toast", "quantity": 1, "unit": "slice"}
    - "a bowl of Cheerios with milk" -> {"name": "Cheerios cereal", ...} and {"name": "milk", ...}
    - "a bottle of water" -> {"name": "water", "quantity": 1, "unit": "bottle"} (keep the volume word — bottle/glass/cup/oz/ml — as the unit for drinks)
    - Supplements count as items too: "5 grams of creatine" -> {"name": "creatine", "quantity": 5, "unit": "grams"}; "a caffeine pill" -> {"name": "caffeine", "quantity": 1, "unit": "pill"}. Keep the dose amount as quantity/unit and set needsClarification false.
    Set needsClarification to true when the description is too vague to estimate macros reliably:
    - the amount is a vague container or quantity word (bag, bowl, handful, some, a bit of) rather than a countable or measurable unit (piece, slice, cup, oz, gram)
    - the name is a brand with multiple product lines and no specific product (e.g. "a Chobani" without flavor or type)
    - the words could plausibly refer to multiple distinct foods
    When needsClarification is true, write one short clarificationQuestion and provide 2 to 4 options the user can tap. Each option needs a short human label plus a fully resolved name, quantity, and countable/measurable unit, favoring realistic single-serving interpretations over bulk or family sizes.
    When needsClarification is false, set clarificationQuestion and options to null.
    If the quantity is merely unstated but the food itself is unambiguous, estimate a reasonable single serving and set needsClarification to false.
    """

    var session: URLSession = .shared

    func parse(_ mealText: String) async throws -> [FoodItemRequest] {
        guard let apiKey = KeychainService.get(.claudeAPIKey) else {
            throw MealParsingError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        // Fail fast in dead zones — the coordinator falls back to on-device
        // parsing instead of leaving the user staring at a spinner for the
        // 60 s system default.
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = MessagesRequest(
            model: "claude-sonnet-4-6",
            maxTokens: 2000,
            system: Self.systemPrompt,
            messages: [.init(role: "user", content: mealText)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MealParsingError.httpError(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text,
              !text.isEmpty
        else { throw MealParsingError.emptyResponse }

        return try Self.decodeItems(from: text)
    }

    /// Extracts the `{"items": [...]}` payload from Claude's text reply.
    /// The prompt forbids markdown fences, but strip them defensively anyway.
    static func decodeItems(from text: String) throws -> [FoodItemRequest] {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // If any preamble slipped in, cut to the outermost JSON object.
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8) else {
            throw MealParsingError.emptyResponse
        }
        do {
            var items = try JSONDecoder().decode(ParsedMealResponse.self, from: data).items
            // Defensive second line of defense: even with the prompt above, a
            // leaked sentence fragment in `name` gets scrubbed here so the raw
            // transcript can never become the item's display name.
            for i in items.indices {
                items[i].name = cleanName(items[i].name)
            }
            return items
        } catch {
            throw MealParsingError.invalidJSON(underlying: error)
        }
    }

    /// Strips first-person/verb/quantity/container lead-ins that occasionally
    /// leak into `name` ("I drank one can of celsius" → "celsius") and collapses
    /// whitespace. Order matters: filler verbs first, then a leading
    /// "<amount> <container> of" phrase.
    static func cleanName(_ raw: String) -> String {
        var name = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        name = stripLeadingVerbs(name)

        // Leading "<amount> <container> of": "one can of", "a glass of",
        // "2 slices of", "a bowl of". Leaves "greek yogurt", "Celsius energy
        // drink", etc. untouched (no "of" after a container word).
        let amountWord = #"(?:a|an|one|two|three|four|five|six|\d+(?:\.\d+)?)"#
        let containerWord = #"(?:can|cans|glass|glasses|bottle|bottles|cup|cups|bowl|bowls|slice|slices|piece|pieces|bag|bags|serving|servings|scoop|scoops|handful|handfuls|packet|packets|container|containers|plate|plates)"#
        let containerPattern = "^\(amountWord)\\s+\(containerWord)\\s+of\\s+"
        name = replacingFirstMatch(in: name, pattern: containerPattern, with: "")

        // Collapse internal whitespace.
        name = name.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // Never return empty — fall back to the original if we over-stripped.
        return trimmed.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : trimmed
    }

    /// Leading first-person verbs: "I ate/drank/had/took/have/got a ...".
    /// Shared with LocalMealParser so both strip the same lead-ins.
    static func stripLeadingVerbs(_ text: String) -> String {
        let verbPattern = #"^(?:i\s+)?(?:ate|drank|had|have|got|grabbed|made|ordered|consumed|took|take|taken)\s+"#
        return replacingFirstMatch(in: text, pattern: verbPattern, with: "")
    }

    private static func replacingFirstMatch(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}

// MARK: - Offline fallback parser

/// On-device fallback used when the Claude API is unreachable (no signal,
/// airplane mode) so an entry can ALWAYS be created. Deliberately simple:
/// each comma/"and" segment becomes one item with a quantity, a unit, and any
/// spoken macro numbers. Water, bare supplements, spoken macros, and
/// previously-corrected foods (RememberedMatchStore) then resolve fully
/// offline in the coordinator; anything else appears as an unmatched card the
/// user completes by hand with Edit. Compound names joined by "and"
/// ("mac and cheese") do get split — an accepted tradeoff; the online parser
/// handles those.
enum LocalMealParser {
    static func parse(_ text: String) -> [FoodItemRequest] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var items: [FoodItemRequest] = []
        for segment in split(trimmed) {
            guard let parsed = parseSegment(segment) else { continue }
            if parsed.name.isEmpty {
                // A macros-only segment ("…, 300 calories") belongs to the
                // item before it.
                guard parsed.hasExplicitMacros, var last = items.popLast() else { continue }
                last.calories = parsed.calories ?? last.calories
                last.protein = parsed.protein ?? last.protein
                last.carbs = parsed.carbs ?? last.carbs
                last.fat = parsed.fat ?? last.fat
                items.append(last)
            } else {
                items.append(parsed)
            }
        }
        // Never return nothing for non-empty text — fall back to one item
        // carrying the whole phrase so the entry can still be created.
        if items.isEmpty {
            items = [FoodItemRequest(
                name: ClaudeMealParsingService.cleanName(trimmed),
                quantity: 1, unit: "serving"
            )]
        }
        return items
    }

    private static func split(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: #"\s+and\s+"#, with: ",", options: [.regularExpression, .caseInsensitive])
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func parseSegment(_ raw: String) -> FoodItemRequest? {
        var s = ClaudeMealParsingService.stripLeadingVerbs(
            raw.trimmingCharacters(in: .whitespaces)
        )

        // Spoken numbers first, so "300" isn't mistaken for a quantity.
        let calories = extractMacro(&s, pattern: #"(\d+(?:\.\d+)?)\s*(?:kcal|calories?|cals?)\b"#)
        let protein = extractMacro(&s, pattern: #"(\d+(?:\.\d+)?)\s*(?:g|grams?)?\s*(?:of\s+)?protein\b"#)
        let carbs = extractMacro(&s, pattern: #"(\d+(?:\.\d+)?)\s*(?:g|grams?)?\s*(?:of\s+)?carb(?:s|ohydrates?)?\b"#)
        let fat = extractMacro(&s, pattern: #"(\d+(?:\.\d+)?)\s*(?:g|grams?)?\s*(?:of\s+)?fat\b"#)

        // Leading "<amount> [unit] [of] <name>".
        var quantity = 1.0
        var unit = "serving"
        let amountPattern = #"^(\d+(?:\.\d+)?|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|half|couple|few)\s+(.+)$"#
        if let (qtyToken, rest) = firstMatch(in: s, pattern: amountPattern) {
            quantity = Double(qtyToken) ?? numberWords[qtyToken.lowercased()] ?? 1
            var remainder = rest
            if let (unitToken, name) = firstMatch(in: remainder, pattern: #"^([a-z]+)\s+(?:of\s+)?(.+)$"#),
               knownUnits.contains(unitToken.lowercased()) {
                unit = unitToken.lowercased()
                remainder = name
            }
            s = remainder
        }

        // Tidy what's left into a shelf-label name.
        s = s.replacingOccurrences(of: #"^(?:with|about|around|roughly|of|and|a|an|the)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s+(?:with|and|of|at|about)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.split(separator: " ").joined(separator: " ")
        let name = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))

        if name.isEmpty, calories == nil, protein == nil, carbs == nil, fat == nil {
            return nil
        }
        return FoodItemRequest(
            name: name, quantity: quantity, unit: unit,
            calories: calories, protein: protein, carbs: carbs, fat: fat
        )
    }

    /// Pull the first match's number out of `text`, removing the matched
    /// phrase so it doesn't leak into the item name.
    private static func extractMacro(_ text: inout String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range, in: text),
              let value = Double(text[valueRange])
        else { return nil }
        text.removeSubrange(fullRange)
        return value
    }

    private static func firstMatch(in text: String, pattern: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let first = Range(match.range(at: 1), in: text),
              let second = Range(match.range(at: 2), in: text)
        else { return nil }
        return (String(text[first]), String(text[second]))
    }

    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "half": 0.5, "couple": 2, "few": 3,
    ]

    private static let knownUnits: Set<String> = [
        "oz", "ounce", "ounces", "g", "gram", "grams", "mg", "milligram", "milligrams",
        "cup", "cups", "glass", "glasses", "bottle", "bottles", "can", "cans",
        "slice", "slices", "piece", "pieces", "scoop", "scoops", "serving", "servings",
        "pill", "pills", "tablet", "tablets", "capsule", "capsules",
        "ml", "milliliter", "milliliters", "l", "liter", "liters",
        "tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons",
        "bar", "bars", "packet", "packets", "bowl", "bowls", "handful", "handfuls",
        "strip", "strips", "container", "containers", "bag", "bags",
    ]
}

// MARK: - Anthropic Messages API wire types

private struct MessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens: Int
    let system: String
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

private struct MessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    let content: [ContentBlock]
}
