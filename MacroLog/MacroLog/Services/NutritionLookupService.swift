import Foundation

protocol NutritionLookup {
    /// Looks up macros for a parsed food item, scaled to its quantity/unit.
    func lookup(_ request: FoodItemRequest) async throws -> NutritionMatch
    /// Raw search, used by the edit screen to let the user swap the matched food.
    func search(query: String) async throws -> [USDAFood]
}

/// Result of matching one parsed item against USDA FoodData Central.
struct NutritionMatch: Equatable {
    var matchedDescription: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var confidence: String
}

enum NutritionLookupError: LocalizedError {
    case httpError(status: Int)
    case noResults

    var errorDescription: String? {
        switch self {
        case .httpError(let status):
            return "USDA FoodData Central returned an error (HTTP \(status))."
        case .noResults:
            return "No matching food was found."
        }
    }
}

struct USDANutritionLookupService: NutritionLookup {
    var session: URLSession = .shared

    func lookup(_ request: FoodItemRequest) async throws -> NutritionMatch {
        let foods = try await search(query: request.name)
        guard let best = Self.bestMatch(for: request.name, in: foods) else {
            throw NutritionLookupError.noResults
        }
        return Self.match(for: request, food: best.food, nameScore: best.score)
    }

    func search(query: String) async throws -> [USDAFood] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: KeychainService.usdaKeyOrDemo),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "10"),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Branded"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NutritionLookupError.httpError(status: http.statusCode)
        }
        return try JSONDecoder().decode(USDASearchResponse.self, from: data).foods
    }

    // MARK: - Matching & scaling (pure functions, unit-tested)

    /// Builds the final match: extracts per-100g macros, converts the requested
    /// quantity to grams, scales, and decides the confidence flag.
    static func match(for request: FoodItemRequest, food: USDAFood, nameScore: Double) -> NutritionMatch {
        let per100g = food.macrosPer100g
        let grams = gramsFor(quantity: request.quantity, unit: request.unit)
        let factor = grams.value / 100.0
        // Low confidence when the food name barely matches or we had to guess
        // what the unit weighs — either way the user should eyeball it.
        let confident = grams.isExact && nameScore >= 0.5
        return NutritionMatch(
            matchedDescription: food.description,
            calories: per100g.calories * factor,
            protein: per100g.protein * factor,
            carbs: per100g.carbs * factor,
            fat: per100g.fat * factor,
            confidence: confident ? MatchConfidence.high : MatchConfidence.low
        )
    }

    /// Picks the search result whose description best overlaps the query,
    /// preferring non-branded (generic) foods on ties.
    static func bestMatch(for name: String, in foods: [USDAFood]) -> (food: USDAFood, score: Double)? {
        let scored = foods.map { food -> (USDAFood, Double) in
            var score = nameMatchScore(query: name, candidate: food.description)
            if food.dataType == "Foundation" || food.dataType == "SR Legacy" {
                score += 0.05 // nudge generic entries ahead of branded ones on near-ties
            }
            return (food, score)
        }
        return scored.max { $0.1 < $1.1 }.map { (food: $0.0, score: min($0.1, 1.0)) }
    }

    /// Fraction of the query's words that appear in the candidate description (0...1).
    static func nameMatchScore(query: String, candidate: String) -> Double {
        let queryTokens = tokens(query)
        guard !queryTokens.isEmpty else { return 0 }
        let candidateTokens = tokens(candidate)
        let hits = queryTokens.filter { q in
            candidateTokens.contains { $0 == q || $0.hasPrefix(q) || q.hasPrefix($0) }
        }
        return Double(hits.count) / Double(queryTokens.count)
    }

    private static func tokens(_ s: String) -> Set<String> {
        Set(
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 1 }
        )
    }

    /// Converts a (quantity, unit) pair to grams. `isExact` is false when the
    /// unit is count-like ("piece", "serving") and we fell back to an assumed
    /// weight — those items get flagged for manual review.
    static func gramsFor(quantity: Double, unit: String) -> (value: Double, isExact: Bool) {
        let normalized = unit.lowercased().trimmingCharacters(in: .whitespaces)
        // Volume units use the density of water as an approximation; close
        // enough for beverages and most cooked foods, still marked exact
        // because the quantity itself was explicit.
        let gramsPerUnit: [String: Double] = [
            "g": 1, "gram": 1, "grams": 1,
            "kg": 1000, "kilogram": 1000, "kilograms": 1000,
            "mg": 0.001,
            "oz": 28.35, "ounce": 28.35, "ounces": 28.35,
            "lb": 453.6, "lbs": 453.6, "pound": 453.6, "pounds": 453.6,
            "ml": 1, "milliliter": 1, "milliliters": 1,
            "l": 1000, "liter": 1000, "liters": 1000,
            "cup": 240, "cups": 240,
            "tbsp": 15, "tablespoon": 15, "tablespoons": 15,
            "tsp": 5, "teaspoon": 5, "teaspoons": 5,
            "fl oz": 29.57, "fluid ounce": 29.57, "fluid ounces": 29.57,
        ]
        if let grams = gramsPerUnit[normalized] {
            return (quantity * grams, true)
        }
        // Count-like unit ("piece", "slice", "medium", "serving", "egg"...):
        // assume 100 g each and flag for review.
        return (quantity * 100, false)
    }
}

// MARK: - USDA FoodData Central wire types

struct USDASearchResponse: Decodable {
    let foods: [USDAFood]
}

struct USDAFood: Decodable, Identifiable, Equatable {
    struct Nutrient: Decodable, Equatable {
        let nutrientId: Int
        let nutrientName: String?
        let unitName: String?
        let value: Double?
    }

    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let foodNutrients: [Nutrient]

    var id: Int { fdcId }

    /// Macros per 100 g / 100 ml, which is how search-result nutrients are reported.
    var macrosPer100g: (calories: Double, protein: Double, carbs: Double, fat: Double) {
        // 1008 = Energy (kcal); Foundation foods sometimes report only the
        // Atwater calculations (2048 specific, 2047 general) instead.
        let calories = nutrientValue(ids: [1008, 2048, 2047])
        let protein = nutrientValue(ids: [1003])
        let carbs = nutrientValue(ids: [1005])
        let fat = nutrientValue(ids: [1004])
        return (calories, protein, carbs, fat)
    }

    private func nutrientValue(ids: [Int]) -> Double {
        for id in ids {
            if let n = foodNutrients.first(where: { $0.nutrientId == id }), let v = n.value {
                return v
            }
        }
        return 0
    }
}
