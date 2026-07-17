import Foundation
import SwiftData

// MARK: - Shared shapes

/// One ingredient as returned by a search provider, in WHOLE-recipe amounts.
/// Macros are optional: Spoonacular supplies them per ingredient, while Edamam
/// and TheMealDB don't — those get filled from USDA at import time.
struct ImportIngredient {
    var name: String
    var quantity: Double
    var unit: String
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    var hasMacros: Bool {
        calories != nil || protein != nil || carbs != nil || fat != nil
    }
}

/// A compact macro tuple for the results-list preview.
struct MacroSummary: Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

/// One recipe found by a live search, before it's imported into the library.
struct RecipeSearchResult: Identifiable {
    let id: String
    var title: String
    var sourceName: String
    var imageURL: URL?
    var servings: Int
    var slot: MealSlot
    /// Whole-recipe ingredient list.
    var ingredients: [ImportIngredient]
    /// Provider's per-serving macros, shown as a preview. Nil when the source
    /// carries no nutrition (macros are computed from ingredients on import).
    var previewPerServing: MacroSummary?
}

/// A source the recipe search can pull from. `isConfigured` gates whether it's
/// queried (providers needing keys stay out until the user adds them).
protocol RecipeSearchProviding {
    var displayName: String { get }
    var isConfigured: Bool { get }
    func search(_ query: String) async throws -> [RecipeSearchResult]
}

// MARK: - Helpers

enum RecipeSearchSupport {
    /// Best-guess meal slot from a title plus any category/dish-type tags a
    /// provider gives. Defaults to `any` when nothing signals a time of day.
    static func slot(title: String, tags: [String]) -> MealSlot {
        let hay = (title + " " + tags.joined(separator: " ")).lowercased()
        func has(_ words: [String]) -> Bool { words.contains { hay.contains($0) } }
        if has(["breakfast", "brunch", "pancake", "oatmeal", "omelet", "omelette", "waffle"]) { return .breakfast }
        if has(["dessert", "snack", "appetizer", "starter", "side dish", "cookie", "smoothie", "bar"]) { return .snack }
        if has(["lunch", "salad", "sandwich", "wrap", "soup"]) { return .lunch }
        if has(["dinner", "main course", "steak", "roast", "curry", "pasta", "stir"]) { return .dinner }
        return .any
    }

    /// Split a free-text measure ("1 1/2 cups", "1/2 cup", "1 lb", "to taste")
    /// into a numeric quantity and a unit string. Falls back to 1 / the whole
    /// text when there's no leading number.
    static func splitMeasure(_ raw: String) -> (quantity: Double, unit: String) {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return (1, "serving") }
        let parts = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var qty = 0.0
        var consumed = 0
        for part in parts {
            if let value = number(from: part) {
                qty += value
                consumed += 1
            } else {
                break
            }
        }
        guard consumed > 0 else { return (1, s) }
        let unit = parts.dropFirst(consumed).joined(separator: " ")
        return (qty, unit.isEmpty ? "serving" : unit)
    }

    /// A decimal, a simple fraction ("1/2"), or nil.
    private static func number(from token: String) -> Double? {
        if let d = Double(token) { return d }
        if token.contains("/") {
            let f = token.split(separator: "/")
            if f.count == 2, let n = Double(f[0]), let d = Double(f[1]), d != 0 { return n / d }
        }
        return nil
    }
}

// MARK: - Spoonacular

/// Spoonacular complexSearch with recipe nutrition. Returns per-ingredient
/// macros, so imported recipes keep the provider's numbers (no USDA fill).
struct SpoonacularProvider: RecipeSearchProviding {
    var session: URLSession = .shared
    var displayName: String { "Spoonacular" }
    private var apiKey: String? { KeychainService.get(.spoonacularAPIKey) }
    var isConfigured: Bool { apiKey != nil }

    func search(_ query: String) async throws -> [RecipeSearchResult] {
        guard let apiKey else { return [] }
        var comps = URLComponents(string: "https://api.spoonacular.com/recipes/complexSearch")!
        comps.queryItems = [
            .init(name: "query", value: query),
            .init(name: "number", value: "10"),
            .init(name: "addRecipeNutrition", value: "true"),
            .init(name: "apiKey", value: apiKey),
        ]
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        try RecipeSearchError.check(response, data, source: displayName)
        return try JSONDecoder().decode(Response.self, from: data).results.map { $0.toResult() }
    }

    private struct Response: Decodable { let results: [Item] }

    private struct Item: Decodable {
        let id: Int
        let title: String
        let image: String?
        let servings: Int?
        let dishTypes: [String]?
        let nutrition: Nutrition?

        struct Nutrition: Decodable {
            let nutrients: [Nutrient]?
            let ingredients: [Ing]?
        }
        struct Nutrient: Decodable { let name: String; let amount: Double }
        struct Ing: Decodable {
            let name: String
            let amount: Double?
            let unit: String?
            let nutrients: [Nutrient]?
        }

        func toResult() -> RecipeSearchResult {
            let servings = max(1, servings ?? 1)
            let ingredients: [ImportIngredient] = (nutrition?.ingredients ?? []).map { ing in
                ImportIngredient(
                    name: ing.name,
                    quantity: ing.amount ?? 1,
                    unit: (ing.unit?.isEmpty == false ? ing.unit! : "serving"),
                    calories: Self.value(ing.nutrients, "Calories"),
                    protein: Self.value(ing.nutrients, "Protein"),
                    carbs: Self.value(ing.nutrients, "Carbohydrates"),
                    fat: Self.value(ing.nutrients, "Fat")
                )
            }
            var preview: MacroSummary?
            if let n = nutrition?.nutrients {
                preview = MacroSummary(
                    calories: Self.value(n, "Calories") ?? 0,
                    protein: Self.value(n, "Protein") ?? 0,
                    carbs: Self.value(n, "Carbohydrates") ?? 0,
                    fat: Self.value(n, "Fat") ?? 0
                )
            }
            return RecipeSearchResult(
                id: "spoonacular-\(id)", title: title, sourceName: "Spoonacular",
                imageURL: image.flatMap(URL.init(string:)), servings: servings,
                slot: RecipeSearchSupport.slot(title: title, tags: dishTypes ?? []),
                ingredients: ingredients, previewPerServing: preview
            )
        }

        static func value(_ nutrients: [Nutrient]?, _ name: String) -> Double? {
            nutrients?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.amount
        }
    }
}

// MARK: - Edamam

/// Edamam Recipe Search v2. Gives whole-recipe totals but not per-ingredient
/// macros, so ingredients are USDA-filled on import.
struct EdamamProvider: RecipeSearchProviding {
    var session: URLSession = .shared
    var displayName: String { "Edamam" }
    private var appID: String? { KeychainService.get(.edamamAppID) }
    private var appKey: String? { KeychainService.get(.edamamAppKey) }
    var isConfigured: Bool { appID != nil && appKey != nil }

    func search(_ query: String) async throws -> [RecipeSearchResult] {
        guard let appID, let appKey else { return [] }
        var comps = URLComponents(string: "https://api.edamam.com/api/recipes/v2")!
        comps.queryItems = [
            .init(name: "type", value: "public"),
            .init(name: "q", value: query),
            .init(name: "app_id", value: appID),
            .init(name: "app_key", value: appKey),
        ]
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 15
        // Newer Edamam plans require the account-user header; the app id is a
        // safe value for a single-user app.
        request.setValue(appID, forHTTPHeaderField: "Edamam-Account-User")
        let (data, response) = try await session.data(for: request)
        try RecipeSearchError.check(response, data, source: displayName)
        return try JSONDecoder().decode(Response.self, from: data).hits.map { $0.recipe.toResult() }
    }

    private struct Response: Decodable { let hits: [Hit] }
    private struct Hit: Decodable { let recipe: Recipe }

    private struct Recipe: Decodable {
        let label: String
        let image: String?
        let url: String?
        let yield: Double?
        let ingredients: [Ing]?
        let totalNutrients: [String: Nutrient]?
        let mealType: [String]?
        let dishType: [String]?

        struct Ing: Decodable {
            let food: String?
            let text: String?
            let quantity: Double?
            let measure: String?
        }
        struct Nutrient: Decodable { let quantity: Double? }

        func toResult() -> RecipeSearchResult {
            let servings = max(1, Int(yield?.rounded() ?? 1))
            let mapped: [ImportIngredient] = (ingredients ?? []).map { ing in
                let measure = ing.measure ?? ""
                let unit = (measure.isEmpty || measure == "<unit>") ? "serving" : measure
                return ImportIngredient(
                    name: ing.food ?? ing.text ?? "ingredient",
                    quantity: ing.quantity ?? 1,
                    unit: unit
                )
            }
            var preview: MacroSummary?
            if let n = totalNutrients {
                let y = max(1, yield ?? 1)
                preview = MacroSummary(
                    calories: (n["ENERC_KCAL"]?.quantity ?? 0) / y,
                    protein: (n["PROCNT"]?.quantity ?? 0) / y,
                    carbs: (n["CHOCDF"]?.quantity ?? 0) / y,
                    fat: (n["FAT"]?.quantity ?? 0) / y
                )
            }
            let stableID = url ?? label
            return RecipeSearchResult(
                id: "edamam-\(stableID.hashValue)", title: label,
                sourceName: "Edamam", imageURL: image.flatMap(URL.init(string:)),
                servings: servings,
                slot: RecipeSearchSupport.slot(title: label, tags: (mealType ?? []) + (dishType ?? [])),
                ingredients: mapped, previewPerServing: preview
            )
        }
    }
}

// MARK: - TheMealDB

/// TheMealDB free search — no key required, but no nutrition either, so every
/// ingredient is USDA-filled on import. All fields come back as strings.
struct TheMealDBProvider: RecipeSearchProviding {
    var session: URLSession = .shared
    var displayName: String { "TheMealDB" }
    var isConfigured: Bool { true } // free, keyless — always available

    func search(_ query: String) async throws -> [RecipeSearchResult] {
        var comps = URLComponents(string: "https://www.themealdb.com/api/json/v1/1/search.php")!
        comps.queryItems = [.init(name: "s", value: query)]
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        try RecipeSearchError.check(response, data, source: displayName)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.meals ?? []).map { Self.toResult($0) }
    }

    private struct Response: Decodable { let meals: [[String: String?]]? }

    private static func toResult(_ meal: [String: String?]) -> RecipeSearchResult {
        func field(_ key: String) -> String? {
            guard let value = meal[key] ?? nil else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let title = field("strMeal") ?? "Recipe"
        var ingredients: [ImportIngredient] = []
        for i in 1...20 {
            guard let name = field("strIngredient\(i)") else { continue }
            let (qty, unit) = RecipeSearchSupport.splitMeasure(field("strMeasure\(i)") ?? "")
            ingredients.append(ImportIngredient(name: name, quantity: qty, unit: unit))
        }
        let id = field("idMeal") ?? title
        return RecipeSearchResult(
            id: "mealdb-\(id)", title: title, sourceName: "TheMealDB",
            imageURL: field("strMealThumb").flatMap(URL.init(string:)),
            servings: 1, // TheMealDB doesn't give a serving count
            slot: RecipeSearchSupport.slot(title: title, tags: [field("strCategory") ?? ""]),
            ingredients: ingredients, previewPerServing: nil
        )
    }
}

// MARK: - Errors

enum RecipeSearchError: LocalizedError {
    case http(source: String, status: Int)

    static func check(_ response: URLResponse, _ data: Data, source: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200..<300).contains(http.statusCode) {
            throw RecipeSearchError.http(source: source, status: http.statusCode)
        }
    }

    var errorDescription: String? {
        switch self {
        case .http(let source, let status):
            return "\(source) returned HTTP \(status)."
        }
    }
}

// MARK: - Aggregator

/// Fans a query out across every configured provider and merges the results,
/// de-duplicating by title. Provider errors are collected, not thrown, so one
/// source being down doesn't sink the others.
struct RecipeSearchAggregator {
    var providers: [RecipeSearchProviding]

    static var configured: RecipeSearchAggregator {
        RecipeSearchAggregator(providers: [
            SpoonacularProvider(), EdamamProvider(), TheMealDBProvider(),
        ])
    }

    var activeProviders: [RecipeSearchProviding] { providers.filter { $0.isConfigured } }

    func search(_ query: String) async -> (results: [RecipeSearchResult], errors: [String]) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], []) }

        var results: [RecipeSearchResult] = []
        var errors: [String] = []
        // Sequential keeps provider existentials off the concurrency-domain
        // hazards of a task group; at most three sources, so latency is fine.
        for provider in activeProviders {
            do {
                results += try await provider.search(trimmed)
            } catch {
                errors.append("\(provider.displayName): \(error.localizedDescription)")
            }
        }

        // De-dup by title (same dish from two sources), keeping the first —
        // Spoonacular/Edamam come before TheMealDB, so richer data wins.
        var seen = Set<String>()
        let deduped = results.filter { seen.insert($0.title.lowercased()).inserted }
        return (deduped, errors)
    }
}

// MARK: - Import

/// Turns a search result into a persisted `Recipe`, scaled to a single serving.
/// Ingredients that arrive without macros (Edamam, TheMealDB) are filled from
/// the USDA lookup so the recipe's totals are real and self-consistent.
enum RecipeImporter {
    @MainActor
    static func makeRecipe(
        from result: RecipeSearchResult,
        lookup: NutritionLookup,
        into context: ModelContext
    ) async -> Recipe {
        let servings = Double(max(1, result.servings))
        var built: [RecipeIngredient] = []

        for (index, ing) in result.ingredients.enumerated() {
            let perServingQty = ing.quantity / servings
            var cal = ing.calories.map { $0 / servings }
            var pro = ing.protein.map { $0 / servings }
            var carb = ing.carbs.map { $0 / servings }
            var fat = ing.fat.map { $0 / servings }
            var confidence = MatchConfidence.high

            if !ing.hasMacros {
                // No provider macros — ask USDA for this single-serving portion.
                let request = FoodItemRequest(name: ing.name, quantity: perServingQty, unit: ing.unit)
                if let match = try? await lookup.lookup(request) {
                    cal = match.calories; pro = match.protein
                    carb = match.carbs; fat = match.fat
                    confidence = match.confidence
                } else {
                    confidence = MatchConfidence.low // couldn't resolve — flag for a look
                }
            }

            built.append(RecipeIngredient(
                name: ing.name, quantity: perServingQty, unit: ing.unit,
                calories: cal ?? 0, protein: pro ?? 0, carbs: carb ?? 0, fat: fat ?? 0,
                matchConfidence: confidence, sortOrder: index
            ))
        }

        // New recipe with its ingredients set at creation — a single insert
        // cascades them (the flaky case is appending to an already-persisted
        // parent, which doesn't apply here).
        let recipe = Recipe(name: result.title, mealSlot: result.slot, ingredients: built)
        context.insert(recipe)
        try? context.save()
        return recipe
    }
}
