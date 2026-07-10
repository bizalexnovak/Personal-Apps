import Foundation

/// One estimated component of a photographed dish.
struct EstimatedFoodItem: Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

struct EstimatedDish: Codable, Equatable {
    var items: [EstimatedFoodItem]
}

protocol DishEstimating {
    func estimate(imageData: Data) async throws -> EstimatedDish
}

/// Sends a photo of a prepared meal (NOT a nutrition label) to Anthropic's
/// Messages API (vision) and asks Claude to identify the foods and estimate
/// their portions and macros. Results are estimates, so the review flow marks
/// every item low-confidence for the user to confirm or adjust.
struct ClaudeDishEstimationService: DishEstimating {
    static let systemPrompt = """
    You estimate nutrition from a photograph of a prepared meal or dish (NOT a nutrition facts label). Identify each distinct food or component you can see and estimate its portion and nutrition. Respond ONLY with valid JSON, no markdown, no preamble.
    Format: {"items": [{"name": string, "quantity": number, "unit": string, "calories": number, "protein": number, "carbs": number, "fat": number}]}
    - One entry per distinct food/component (e.g. "grilled chicken breast", "white rice", "steamed broccoli"). Combine garnishes into the main item.
    - "name": a short food name (no brand unless clearly visible).
    - "quantity" + "unit": your best portion estimate using natural units ("g", "oz", "cup", "piece", "serving").
    - calories (kcal), protein, carbs, fat (grams): your best per-portion estimate for what's shown.
    Estimate realistic values from visible portion sizes. It's fine to estimate; never return an empty list if there is food in the photo.
    """

    var session: URLSession = .shared

    func estimate(imageData: Data) async throws -> EstimatedDish {
        guard let apiKey = KeychainService.get(.claudeAPIKey) else {
            throw MealParsingError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = VisionRequest(
            model: "claude-sonnet-4-6",
            maxTokens: 1024,
            system: Self.systemPrompt,
            messages: [
                .init(role: "user", content: [
                    .image(mediaType: "image/jpeg", data: imageData.base64EncodedString()),
                    .text("Estimate the nutrition of this dish."),
                ])
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MealParsingError.httpError(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        let decoded = try JSONDecoder().decode(VisionResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text, !text.isEmpty else {
            throw MealParsingError.emptyResponse
        }
        return try Self.decode(from: text)
    }

    static func decode(from text: String) throws -> EstimatedDish {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8) else {
            throw MealParsingError.emptyResponse
        }
        do {
            return try JSONDecoder().decode(EstimatedDish.self, from: data)
        } catch {
            throw MealParsingError.invalidJSON(underlying: error)
        }
    }
}

// MARK: - Anthropic vision wire types (local copy to keep the service self-contained)

private struct VisionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: [Block]
    }

    enum Block: Encodable {
        case text(String)
        case image(mediaType: String, data: String)

        enum CodingKeys: String, CodingKey { case type, text, source }
        enum SourceKeys: String, CodingKey { case type, mediaType = "media_type", data }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let value):
                try container.encode("text", forKey: .type)
                try container.encode(value, forKey: .text)
            case .image(let mediaType, let data):
                try container.encode("image", forKey: .type)
                var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
                try source.encode("base64", forKey: .type)
                try source.encode(mediaType, forKey: .mediaType)
                try source.encode(data, forKey: .data)
            }
        }
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

private struct VisionResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    let content: [ContentBlock]
}
