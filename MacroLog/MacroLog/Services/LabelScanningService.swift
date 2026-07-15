import Foundation

/// Macros extracted directly from a photographed nutrition-facts label. Label
/// data is authoritative, so this skips USDA entirely. Micronutrient fields are
/// optional — present only when printed on the label.
struct LabelNutrition: Codable, Equatable {
    var name: String
    var servingSize: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    // Micronutrients as printed (nil when not on the label).
    var saturatedFat: Double?
    var transFat: Double?
    var cholesterol: Double?
    var sodium: Double?
    var fiber: Double?
    var totalSugars: Double?
    var addedSugars: Double?
    var potassium: Double?
    var calcium: Double?
    var iron: Double?
    var magnesium: Double?
    var zinc: Double?
    var phosphorus: Double?
    var copper: Double?
    var manganese: Double?
    var selenium: Double?
    var vitaminA: Double?
    var vitaminC: Double?
    var vitaminD: Double?
    var vitaminE: Double?
    var vitaminK: Double?
    var thiamin: Double?
    var riboflavin: Double?
    var niacin: Double?
    var vitaminB6: Double?
    var folate: Double?
    var vitaminB12: Double?
    var caffeine: Double?
    var creatine: Double?

    /// The micronutrient values a label carries, mapped into the shared type.
    var micronutrients: Micronutrients {
        Micronutrients(
            saturatedFat: saturatedFat,
            transFat: transFat,
            fiber: fiber,
            totalSugars: totalSugars,
            addedSugars: addedSugars,
            cholesterol: cholesterol,
            sodium: sodium,
            potassium: potassium,
            calcium: calcium,
            iron: iron,
            magnesium: magnesium,
            zinc: zinc,
            phosphorus: phosphorus,
            copper: copper,
            manganese: manganese,
            selenium: selenium,
            vitaminA: vitaminA,
            vitaminC: vitaminC,
            vitaminD: vitaminD,
            vitaminE: vitaminE,
            vitaminK: vitaminK,
            thiamin: thiamin,
            riboflavin: riboflavin,
            niacin: niacin,
            vitaminB6: vitaminB6,
            folate: folate,
            vitaminB12: vitaminB12,
            caffeine: caffeine,
            creatine: creatine
        )
    }
}

protocol LabelScanning {
    func scan(imageData: Data) async throws -> LabelNutrition
}

/// Sends a nutrition-label photo to Anthropic's Messages API (vision) and
/// parses the macros out of the image.
struct ClaudeLabelScanningService: LabelScanning {
    static let systemPrompt = """
    You read nutrition facts and supplement facts labels from photographs. Extract the values for ONE serving as printed on the label. Respond ONLY with valid JSON, no markdown, no preamble.
    Format: {"name": string, "servingSize": string, "calories": number, "protein": number, "carbs": number, "fat": number, "saturatedFat": number|null, "transFat": number|null, "cholesterol": number|null, "sodium": number|null, "fiber": number|null, "totalSugars": number|null, "addedSugars": number|null, "potassium": number|null, "calcium": number|null, "iron": number|null, "magnesium": number|null, "zinc": number|null, "phosphorus": number|null, "copper": number|null, "manganese": number|null, "selenium": number|null, "vitaminA": number|null, "vitaminC": number|null, "vitaminD": number|null, "vitaminE": number|null, "vitaminK": number|null, "thiamin": number|null, "riboflavin": number|null, "niacin": number|null, "vitaminB6": number|null, "folate": number|null, "vitaminB12": number|null, "caffeine": number|null, "creatine": number|null}
    - "name": the product name if visible on the packaging, otherwise a short generic description of the food.
    - "servingSize": the serving size exactly as printed (e.g. "1 can (12 fl oz)", "2/3 cup (55g)").
    - calories, protein, carbs, fat: the per-serving numbers in kcal and grams. If a macro is genuinely not on the label, use 0.
    - saturatedFat, transFat, fiber, totalSugars, addedSugars, creatine: grams per serving.
    - cholesterol, sodium, potassium, calcium, iron, magnesium, zinc, phosphorus, copper, manganese, vitaminC, vitaminE, thiamin, riboflavin, niacin, vitaminB6, caffeine: milligrams (mg) per serving.
    - vitaminA, vitaminD, vitaminK, selenium, folate, vitaminB12: micrograms (mcg) per serving.
    - Convert if the label prints a different unit (e.g. vitamin A in IU ≈ printed IU × 0.3 mcg for retinol; 1 g = 1000 mg = 1000000 mcg).
    - caffeine: often printed outside the facts panel ("Caffeine content: 200 mg") — include it if printed anywhere on the visible packaging.
    - creatine: on supplement facts panels (e.g. "Creatine monohydrate 5 g").
    - For every micronutrient field: use the printed number, or null if that nutrient is not shown on the label. Do NOT use 0 for a missing micronutrient, and do not estimate.
    Read the printed numbers only — do not infer values that aren't shown.
    """

    var session: URLSession = .shared

    func scan(imageData: Data) async throws -> LabelNutrition {
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
                    .text("Extract the nutrition facts from this label."),
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

    static func decode(from text: String) throws -> LabelNutrition {
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
            return try JSONDecoder().decode(LabelNutrition.self, from: data)
        } catch {
            throw MealParsingError.invalidJSON(underlying: error)
        }
    }
}

// MARK: - Anthropic vision wire types

private struct VisionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: [Block]
    }

    /// A user content block: either text or a base64 image source.
    enum Block: Encodable {
        case text(String)
        case image(mediaType: String, data: String)

        enum CodingKeys: String, CodingKey {
            case type, text, source
        }
        enum SourceKeys: String, CodingKey {
            case type, mediaType = "media_type", data
        }

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
