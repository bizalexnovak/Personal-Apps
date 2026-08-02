import Foundation
import SwiftData

/// Two-way sync between this device's food database and the shared community
/// database on the proxy server (see `server/worker.js`):
///
///  - **Push**: rows this user added (scans, CSV imports) that haven't been
///    uploaded yet. Everyone's scans make matching better for everyone.
///  - **Pull**: rows other users contributed since the last sync, merged in
///    through the same dedup key as every other source.
///
/// Only active when the proxy is configured (invite-code users). Direct-key
/// users simply keep a personal database — nothing breaks, nothing syncs.
/// All failures are silent-but-logged: sync is a background nicety, never a
/// blocker for logging food.
enum CommunitySync {
    private static let cursorKey = "community_food_sync_cursor"
    private static var session: URLSession { .shared }

    /// Wire format for one food row (matches the Worker's table).
    struct WireFood: Codable {
        var name: String
        var brand: String
        var serving: String
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var micros: String?
        var source: String
        var createdAt: Double?

        enum CodingKeys: String, CodingKey {
            case name, brand, serving, calories, protein, carbs, fat, micros, source
            case createdAt = "created_at"
        }
    }

    // MARK: - Entry points

    /// Fire-and-forget push after new local rows (scan / import).
    @MainActor
    static func pushSoon(context: ModelContext) {
        Task { await push(context: context) }
    }

    /// Full sync — called on app launch.
    @MainActor
    static func syncNow(context: ModelContext) async {
        await push(context: context)
        await pull(context: context)
    }

    // MARK: - Push

    /// The only row sources that may be shared: published nutrition facts a
    /// user photographed off a package, and nutrition sheets they uploaded.
    /// Anything else stays on the device. This is the privacy policy expressed
    /// as code — a new row source is private until it is deliberately added
    /// here, rather than shared by default because someone forgot.
    static let shareableSources: Set<String> = ["scan", "import"]

    @MainActor
    static func push(context: ModelContext) async {
        guard let (base, code) = ClaudeEndpoint.proxyConfig else { return }
        let unsynced = (try? context.fetch(FetchDescriptor<CustomFood>(
            predicate: #Predicate { $0.synced == false }
        ))) ?? []
        let pending = unsynced.filter { shareableSources.contains($0.source) }
        guard !pending.isEmpty else { return }

        let items = pending.map { food in
            WireFood(
                name: food.name, brand: food.brand, serving: food.serving,
                calories: food.calories, protein: food.protein,
                carbs: food.carbs, fat: food.fat,
                micros: food.microsData.flatMap { String(data: $0, encoding: .utf8) },
                source: food.source
            )
        }
        var request = URLRequest(url: base.appendingPathComponent("foods"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(code, forHTTPHeaderField: "x-foob-user")
        request.httpBody = try? JSONEncoder().encode(["items": items])

        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return } // stays unsynced; retried next push
        for food in pending { food.synced = true }
        try? context.save()
    }

    // MARK: - Pull

    /// The server pages at 500 rows; keep requesting until caught up (with a
    /// per-launch page cap so a huge backlog can't stall startup — the next
    /// launch resumes from the saved cursor).
    @MainActor
    static func pull(context: ModelContext, maxPages: Int = 10) async {
        guard let (base, code) = ClaudeEndpoint.proxyConfig else { return }

        struct PullResponse: Codable {
            var items: [WireFood]
            var next: Double?
        }

        for _ in 0..<maxPages {
            var comps = URLComponents(url: base.appendingPathComponent("foods"), resolvingAgainstBaseURL: false)!
            let since = UserDefaults.standard.double(forKey: cursorKey)
            comps.queryItems = [URLQueryItem(name: "since", value: String(Int(since)))]
            var request = URLRequest(url: comps.url!)
            request.timeoutInterval = 15
            request.setValue(code, forHTTPHeaderField: "x-foob-user")

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let decoded = try? JSONDecoder().decode(PullResponse.self, from: data)
            else { return }

            for item in decoded.items {
                CustomFoodStore.addIfNew(CustomFood(
                    name: item.name, brand: item.brand, serving: item.serving,
                    calories: item.calories, protein: item.protein,
                    carbs: item.carbs, fat: item.fat,
                    microsData: item.micros?.data(using: .utf8),
                    source: "community", synced: true
                ), in: context)
            }
            if !decoded.items.isEmpty { try? context.save() }
            if let next = decoded.next, next > since {
                UserDefaults.standard.set(next, forKey: cursorKey)
            }
            // A short page means we're caught up.
            if decoded.items.count < 500 { return }
        }
    }

    // MARK: - Recipes

    /// Publish one recipe to the shared library. Returns true on success.
    @MainActor
    static func shareRecipe(_ recipe: Recipe) async -> Bool {
        guard let (base, code) = ClaudeEndpoint.proxyConfig else { return false }
        struct WireIngredient: Codable {
            var name: String; var quantity: Double; var unit: String
            var calories: Double; var protein: Double; var carbs: Double; var fat: Double
        }
        let ingredients = recipe.sortedIngredients.map {
            WireIngredient(name: $0.name, quantity: $0.quantity, unit: $0.unit,
                           calories: $0.calories, protein: $0.protein,
                           carbs: $0.carbs, fat: $0.fat)
        }
        let payload: [String: String] = [
            "name": recipe.name,
            "slot": recipe.mealSlot,
            "instructions": recipe.instructions,
            "ingredients": (try? JSONEncoder().encode(ingredients))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]",
        ]
        var request = URLRequest(url: base.appendingPathComponent("recipes"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(code, forHTTPHeaderField: "x-foob-user")
        request.httpBody = try? JSONEncoder().encode(payload)
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return false }
        return true
    }
}

/// Recipes shared by other users of the same proxy server, as a source in the
/// recipe search alongside TheMealDB/Spoonacular/Edamam.
struct CommunityRecipeProvider: RecipeSearchProviding {
    var session: URLSession = .shared
    var displayName: String { "Community" }
    var isConfigured: Bool { ClaudeEndpoint.proxyConfig != nil }

    func search(_ query: String) async throws -> [RecipeSearchResult] {
        guard let (base, code) = ClaudeEndpoint.proxyConfig else { return [] }
        var comps = URLComponents(
            url: base.appendingPathComponent("recipes/search"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 15
        request.setValue(code, forHTTPHeaderField: "x-foob-user")
        let (data, response) = try await session.data(for: request)
        try RecipeSearchError.check(response, data, source: displayName)

        struct WireRecipe: Codable {
            var name: String
            var slot: String?
            var instructions: String?
            var ingredients: String?
        }
        struct SearchResponse: Codable { var items: [WireRecipe] }
        struct WireIngredient: Codable {
            var name: String; var quantity: Double; var unit: String
            var calories: Double; var protein: Double; var carbs: Double; var fat: Double
        }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.items.map { wire in
            let parsed: [WireIngredient] = wire.ingredients
                .flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONDecoder().decode([WireIngredient].self, from: $0) } ?? []
            return RecipeSearchResult(
                id: "community-\(wire.name.lowercased())",
                title: wire.name,
                sourceName: "Community",
                imageURL: nil,
                servings: 1, // shared recipes are stored per serving already
                slot: wire.slot.flatMap(MealSlot.init(rawValue:)) ?? .any,
                ingredients: parsed.map {
                    ImportIngredient(
                        name: $0.name, quantity: $0.quantity, unit: $0.unit,
                        calories: $0.calories, protein: $0.protein,
                        carbs: $0.carbs, fat: $0.fat
                    )
                },
                previewPerServing: nil,
                instructions: wire.instructions ?? ""
            )
        }
    }
}
