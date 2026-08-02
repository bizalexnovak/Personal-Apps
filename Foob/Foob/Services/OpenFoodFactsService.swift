import Foundation

/// Last rung of the match ladder: Open Food Facts, the open community
/// database of ~3M branded products (openfoodfacts.org). Free API, no key.
/// Queried only after the local database and USDA both miss — it shines on
/// branded/international products USDA lacks. Results are marked
/// low-confidence so the review card asks for a look.
/// Injection seam, mirroring `NutritionLookup` and `MealParsing`. Without it
/// the coordinator's last rung reaches the live Open Food Facts API during
/// unit tests, so a test that mocks USDA into finding nothing still gets a
/// match — and passes or fails depending on the network.
protocol OpenFoodFactsLooking {
    func lookup(_ request: FoodItemRequest) async throws -> NutritionMatch?
}

struct OpenFoodFactsService: OpenFoodFactsLooking {
    var session: URLSession = .shared

    func lookup(_ request: FoodItemRequest) async throws -> NutritionMatch? {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            .init(name: "search_terms", value: request.name),
            .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"),
            .init(name: "json", value: "1"),
            .init(name: "page_size", value: "5"),
            .init(name: "fields", value: "product_name,brands,serving_size,nutriments"),
        ]
        var urlRequest = URLRequest(url: comps.url!)
        urlRequest.timeoutInterval = 12 // fail fast; this is a bonus source
        let (data, response) = try await session.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NutritionLookupError.httpError(status: http.statusCode)
        }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return Self.match(for: request, products: decoded.products ?? [])
    }

    /// Pick the first product with usable calories and build the match.
    /// Separated from the network call for testability.
    static func match(for request: FoodItemRequest, products: [Product]) -> NutritionMatch? {
        for product in products {
            guard let n = product.nutriments else { continue }
            // Per-serving values when the product declares a serving,
            // otherwise per 100 g/ml treated as one serving.
            let perServing = n.value("energy-kcal_serving") != nil
            let suffix = perServing ? "_serving" : "_100g"
            guard let kcal = n.value("energy-kcal" + suffix), kcal >= 0 else { continue }

            let servings = CustomFoodStore.countableUnits.contains(NameTokens.normalizedUnit(request.unit))
                ? max(request.quantity, 1)
                : 1
            var micros = Micronutrients()
            // OFF stores sodium/salt in grams; the app tracks sodium in mg.
            if let sodium = n.value("sodium" + suffix) { micros.sodium = sodium * 1000 }
            if let sugars = n.value("sugars" + suffix) { micros.totalSugars = sugars }
            if let fiber = n.value("fiber" + suffix) { micros.fiber = fiber }
            if let satFat = n.value("saturated-fat" + suffix) { micros.saturatedFat = satFat }
            if let caffeine = n.value("caffeine" + suffix) { micros.caffeine = caffeine * 1000 } // g → mg

            let name = [product.product_name, product.brands]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " — ")
            let servingText = perServing
                ? (product.serving_size?.isEmpty == false ? product.serving_size! : "1 serving")
                : "100 g"
            return NutritionMatch(
                matchedDescription: "\(name.isEmpty ? request.name : name) · \(servingText) (Open Food Facts)",
                calories: kcal * servings,
                protein: (n.value("proteins" + suffix) ?? 0) * servings,
                carbs: (n.value("carbohydrates" + suffix) ?? 0) * servings,
                fat: (n.value("fat" + suffix) ?? 0) * servings,
                confidence: MatchConfidence.low, // community data — worth a glance
                micros: micros.scaled(by: servings)
            )
        }
        return nil
    }

    // MARK: - Wire types

    struct SearchResponse: Decodable {
        let products: [Product]?
    }

    struct Product: Decodable {
        let product_name: String?
        let brands: String?
        let serving_size: String?
        let nutriments: Nutriments?
    }

    /// OFF nutriment values arrive as numbers OR strings depending on the
    /// contributor — normalize both to Double.
    struct Nutriments: Decodable {
        let raw: [String: Double]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            var values: [String: Double] = [:]
            for key in container.allKeys {
                if let d = try? container.decode(Double.self, forKey: key) {
                    values[key.stringValue] = d
                } else if let s = try? container.decode(String.self, forKey: key),
                          let d = Double(s) {
                    values[key.stringValue] = d
                }
            }
            raw = values
        }

        func value(_ key: String) -> Double? { raw[key] }

        struct DynamicKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
    }
}
