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
    Format: {"items": [{"name": string, "quantity": number, "unit": string, "needsClarification": boolean, "clarificationQuestion": string or null, "options": [{"label": string, "name": string, "quantity": number, "unit": string}] or null}]}
    CRITICAL — the "name" field must contain ONLY the clean food or product name, never the user's sentence. Strip out first-person phrasing ("I ate", "I drank", "I had"), verbs, articles, quantities, and container words — those belong in "quantity" and "unit", not "name". The name should read like a label on a shelf: a few words at most.
    Examples:
    - "I drank one can of celsius" -> {"name": "Celsius energy drink", "quantity": 1, "unit": "can"}
    - "had two scrambled eggs and a slice of sourdough toast" -> two items: {"name": "scrambled eggs", "quantity": 2, "unit": "large"} and {"name": "sourdough toast", "quantity": 1, "unit": "slice"}
    - "a bowl of Cheerios with milk" -> {"name": "Cheerios cereal", ...} and {"name": "milk", ...}
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

        // Leading first-person verbs: "I ate/drank/had/have/got a ..."
        let verbPattern = #"^(?:i\s+)?(?:ate|drank|had|have|got|grabbed|made|ordered|consumed)\s+"#
        name = replacingFirstMatch(in: name, pattern: verbPattern, with: "")

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

    private static func replacingFirstMatch(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
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
