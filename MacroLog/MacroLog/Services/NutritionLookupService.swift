import Foundation
import os

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

    private static let usdaLogger = Logger(subsystem: "com.alexnovak.macrolog", category: "usda")

    func lookup(_ request: FoodItemRequest) async throws -> NutritionMatch {
        // Full branded phrases ("Chobani mixed berry greek yogurt") often
        // return zero results from FDC's search. Walk a ladder of simpler
        // queries — full phrase, brand + product, product, brand — and rank
        // whatever the first non-empty response returns against the ORIGINAL
        // name. Every attempt is recorded in the diagnostics.
        var attempts: [String] = []
        var foods: [USDAFood] = []
        do {
            for query in Self.queryLadder(for: request.name) {
                let results = try await search(query: query)
                attempts.append("\"\(query)\" → \(results.count) results")
                if !results.isEmpty {
                    foods = results
                    break
                }
            }
        } catch {
            attempts.append("→ request failed: \(error.localizedDescription)")
            await Self.record(MatchDiagnostics(
                request: request,
                queryAttempts: attempts,
                candidates: [],
                selectedDescription: nil,
                selectionReason: "search request failed",
                gramsBasis: "-",
                flags: [],
                resultSummary: "failed — needs manual resolution"
            ))
            throw error
        }

        guard let selection = Self.selectCandidate(for: request, in: foods) else {
            await Self.record(MatchDiagnostics(
                request: request,
                queryAttempts: attempts,
                candidates: Self.candidateSummaries(for: request, in: foods),
                selectedDescription: nil,
                selectionReason: "no candidates from any query",
                gramsBasis: "-",
                flags: [],
                resultSummary: "no match — needs manual resolution"
            ))
            throw NutritionLookupError.noResults
        }

        // Generic (non-branded) foods carry their unit weights in the detail
        // endpoint's foodPortions, not in search results — fetch when the unit
        // might need them. Fail-soft: no portions just means coarser scaling.
        var portions: [USDAPortion] = []
        let unitKind = Self.classifyUnit(request.unit)
        if Self.wantsPortions(unitKind: unitKind, food: selection.food) {
            portions = (try? await fetchPortions(fdcId: selection.food.fdcId)) ?? []
        }

        let evaluation = Self.evaluate(
            for: request,
            food: selection.food,
            nameScore: selection.score,
            portions: portions
        )

        await Self.record(MatchDiagnostics(
            request: request,
            queryAttempts: attempts,
            candidates: Self.candidateSummaries(for: request, in: foods),
            selectedDescription: selection.food.description,
            selectionReason: selection.reason,
            gramsBasis: evaluation.grams.basis,
            flags: evaluation.flags,
            resultSummary: String(
                format: "%.0f kcal · P %.1f · C %.1f · F %.1f — %@",
                evaluation.match.calories, evaluation.match.protein,
                evaluation.match.carbs, evaluation.match.fat,
                evaluation.match.confidence
            )
        ))

        return evaluation.match
    }

    func search(query: String) async throws -> [USDAFood] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: KeychainService.usdaKeyOrDemo),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "10"),
            URLQueryItem(name: "dataType", value: "Branded,Survey (FNDDS),SR Legacy,Foundation"),
        ]
        // Never log the full URL — it carries the api_key.
        Self.usdaLogger.debug("USDA search query: \(query, privacy: .public)")
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let snippet = String(decoding: data.prefix(300), as: UTF8.self)
            Self.usdaLogger.error("USDA HTTP \(http.statusCode, privacy: .public): \(snippet, privacy: .public)")
            throw NutritionLookupError.httpError(status: http.statusCode)
        }
        let foods = try JSONDecoder().decode(USDASearchResponse.self, from: data).foods
        if foods.isEmpty {
            let snippet = String(decoding: data.prefix(300), as: UTF8.self)
            Self.usdaLogger.debug("USDA zero results for \"\(query, privacy: .public)\"; raw response starts: \(snippet, privacy: .public)")
        } else {
            Self.usdaLogger.debug("USDA \(foods.count, privacy: .public) results for \"\(query, privacy: .public)\"")
        }
        return foods
    }

    /// Progressively simpler queries for a food name, BRAND-FIRST. The first
    /// word is treated as the most identifying token (usually the brand), so
    /// brand-specific queries are exhausted before generic category terms —
    /// otherwise "energy drink" matches a wrong product before "Celsius" is
    /// ever tried, since the ladder stops at the first non-empty result.
    /// For "Celsius energy drink":
    ///   full → "Celsius drink" → "Celsius" → "energy drink" → "drink"
    static func queryLadder(for name: String) -> [String] {
        let words = name.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        var ladder = [name]
        if words.count >= 3 {
            // Brand + head noun, e.g. "Celsius drink" / "Chobani yogurt".
            ladder.append("\(words[0]) \(words[words.count - 1])")
        }
        if words.count >= 2 {
            // Brand alone, e.g. "Celsius" / "Chobani".
            ladder.append(words[0])
        }
        if words.count >= 3 {
            // Generic category (drops the brand) — tried only after the
            // brand-specific queries above, since it's the likeliest mismatch.
            ladder.append(words.suffix(2).joined(separator: " "))
        }
        if words.count >= 2 {
            // Last word as a final fallback.
            ladder.append(words[words.count - 1])
        }
        var seen = Set<String>()
        return ladder.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Fetches the detail record's foodPortions ("1 cup" = 158 g, "1 slice" = 28 g, ...).
    func fetchPortions(fdcId: Int) async throws -> [USDAPortion] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/food/\(fdcId)")!
        components.queryItems = [URLQueryItem(name: "api_key", value: KeychainService.usdaKeyOrDemo)]
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NutritionLookupError.httpError(status: http.statusCode)
        }
        return try JSONDecoder().decode(USDAFoodDetail.self, from: data).foodPortions ?? []
    }

    /// Portions are only worth a second request when the unit isn't already an
    /// exact weight, and the search result didn't carry usable serving data.
    static func wantsPortions(unitKind: UnitKind, food: USDAFood) -> Bool {
        switch unitKind {
        case .weight:
            return false
        case .volume:
            return true // a real "1 cup" gram weight beats the water-density approximation
        case .discrete, .serving, .vague, .unknown:
            return servingInfo(for: food) == nil
        }
    }

    // MARK: - Candidate selection

    /// Picks the search result to use, ranking by:
    ///  1. brand-in-description — the candidate's description contains the
    ///     query's first word (usually the brand). A generic "energy drink"
    ///     entry won't contain "Celsius", so a real Celsius entry wins even if
    ///     it came from a later ladder rung.
    ///  2. brand mention — the food's brand metadata matches a query token
    ///  3. unit compatibility — for discrete/serving units, prefer entries whose
    ///     package serving actually describes such a unit ("1 slice" = 15 g)
    ///  4. data-type priority — unit-aware (see `dataTypePriority`)
    ///  5. name-overlap score
    static func selectCandidate(
        for request: FoodItemRequest,
        in foods: [USDAFood]
    ) -> (food: USDAFood, score: Double, reason: String)? {
        guard !foods.isEmpty else { return nil }
        let unitKind = classifyUnit(request.unit)
        let brandWord = request.name.split(separator: " ").first.map(String.init)

        let scored = foods.map { (food: $0, score: nameMatchScore(query: request.name, candidate: $0.description)) }
        let topScore = scored.map(\.score).max() ?? 0
        let threshold = max(0.34, topScore - 0.2)
        var contenders = scored.filter { $0.score >= threshold }
        if contenders.isEmpty {
            contenders = scored.sorted { $0.score > $1.score }.prefix(1).map { $0 }
        }

        let ranked = contenders.map { candidate -> (food: USDAFood, score: Double, key: [Double], reason: String) in
            let brandDesc = descriptionContainsBrand(brandWord: brandWord, food: candidate.food) ? 1.0 : 0.0
            let brand = brandMentioned(query: request.name, food: candidate.food) ? 1.0 : 0.0
            let compat = Double(unitCompatibility(unitKind: unitKind, food: candidate.food, requestUnit: request.unit))
            let priority = Double(dataTypePriority(candidate.food.dataType, unitKind: unitKind))
            var reasons: [String] = []
            if brandDesc > 0, let brandWord { reasons.append("description contains '\(brandWord)'") }
            if brand > 0 { reasons.append("brand mentioned in query") }
            if compat > 0, let info = servingInfo(for: candidate.food) {
                reasons.append("package serving '\(info.rawText)' = \(Int(info.gramsPerServing.rounded())) g")
            }
            reasons.append("\(candidate.food.dataType ?? "?") priority for unit '\(request.unit)'")
            reasons.append(String(format: "name score %.2f", candidate.score))
            return (candidate.food, candidate.score, [brandDesc, brand, compat, priority, candidate.score], reasons.joined(separator: "; "))
        }

        let best = ranked.max { lexicographicallyLess($0.key, $1.key) }
        return best.map { (food: $0.food, score: $0.score, reason: $0.reason) }
    }

    /// True when the candidate's description contains the query's first word
    /// (typically the brand), case-insensitive. Skips 1-character words.
    static func descriptionContainsBrand(brandWord: String?, food: USDAFood) -> Bool {
        guard let brandWord, brandWord.count > 1 else { return false }
        return food.description.range(of: brandWord, options: .caseInsensitive) != nil
    }

    private static func lexicographicallyLess(_ a: [Double], _ b: [Double]) -> Bool {
        for (x, y) in zip(a, b) where x != y {
            return x < y
        }
        return false
    }

    /// Unit-aware data-type priority (user-approved deviation from blanket
    /// Branded-first): Branded serving sizes are what we need for discrete and
    /// serving units, while for explicit weights/volumes Branded per-100g data
    /// is often raw/dry — there, FNDDS "as eaten" entries are the right scale.
    static func dataTypePriority(_ dataType: String?, unitKind: UnitKind) -> Int {
        let type = dataType ?? ""
        switch unitKind {
        case .weight, .volume:
            switch type {
            case "Survey (FNDDS)": return 3
            case "SR Legacy", "Foundation": return 2
            case "Branded": return 1
            default: return 0
            }
        case .discrete, .serving, .vague, .unknown:
            switch type {
            case "Branded": return 3
            case "Survey (FNDDS)": return 2
            case "SR Legacy", "Foundation": return 1
            default: return 0
            }
        }
    }

    static func brandMentioned(query: String, food: USDAFood) -> Bool {
        let brandText = [food.brandOwner, food.brandName].compactMap { $0 }.joined(separator: " ")
        guard !brandText.isEmpty else { return false }
        let brandTokens = tokens(brandText).filter { $0.count > 2 && $0 != "llc" && $0 != "inc" && $0 != "company" }
        return !tokens(query).intersection(brandTokens).isEmpty
    }

    /// 2 = serving text describes a discrete unit (usable per-piece weight),
    /// 1 = has a gram serving size at all, 0 = nothing. Only meaningful when
    /// the requested unit is discrete/serving/unknown.
    static func unitCompatibility(unitKind: UnitKind, food: USDAFood, requestUnit: String) -> Int {
        switch unitKind {
        case .weight, .volume:
            return 0
        case .discrete, .serving, .vague, .unknown:
            guard let info = servingInfo(for: food) else { return 0 }
            return isDiscreteWord(info.descriptor) ? 2 : 1
        }
    }

    // MARK: - Unit classification

    enum UnitKind: Equatable {
        case weight(gramsPerUnit: Double)
        case volume(gramsPerUnit: Double) // water-density approximation
        case discrete(word: String)       // piece, slice, strip, large, ...
        case serving                      // serving, container, package, ...
        case vague(word: String)          // bag, bowl, handful, some, bit, ...
        case unknown
    }

    private static let weightUnits: [String: Double] = [
        "g": 1, "gram": 1, "kg": 1000, "kilogram": 1000, "mg": 0.001,
        "oz": 28.35, "ounce": 28.35, "lb": 453.6, "pound": 453.6,
    ]

    private static let volumeUnits: [String: Double] = [
        "ml": 1, "milliliter": 1, "l": 1000, "liter": 1000,
        "cup": 240, "tbsp": 15, "tablespoon": 15, "tsp": 5, "teaspoon": 5,
        "fl oz": 29.57, "fluid ounce": 29.57,
    ]

    private static let discreteWords: Set<String> = [
        "piece", "slice", "strip", "link", "patty", "pattie", "stick", "item",
        "each", "unit", "egg", "rasher", "meatball", "cookie", "pancake",
        "waffle", "muffin", "bagel", "roll", "bun", "tortilla", "bar",
        "breast", "thigh", "wing", "filet", "fillet", "sausage", "whole",
        "small", "medium", "large",
    ]

    private static let servingWords: Set<String> = [
        "serving", "container", "package", "pouch", "bottle", "can", "carton", "packet",
    ]

    /// Amount words too vague to scale against database entries — these must
    /// go through the clarification flow, and if they somehow reach a lookup
    /// unresolved they are never treated as reliable.
    private static let vagueWords: Set<String> = [
        "bag", "bowl", "handful", "some", "bit", "few", "couple", "little",
        "splash", "dash",
    ]

    static func classifyUnit(_ unit: String) -> UnitKind {
        let normalized = singular(unit.lowercased().trimmingCharacters(in: .whitespaces))
        if let grams = weightUnits[normalized] { return .weight(gramsPerUnit: grams) }
        if let grams = volumeUnits[normalized] { return .volume(gramsPerUnit: grams) }
        if vagueWords.contains(normalized) { return .vague(word: normalized) }
        if discreteWords.contains(normalized) { return .discrete(word: normalized) }
        if servingWords.contains(normalized) { return .serving }
        return .unknown
    }

    static func isDiscreteWord(_ word: String) -> Bool {
        discreteWords.contains(singular(word.lowercased()))
    }

    private static func singular(_ word: String) -> String {
        if word.hasSuffix("es"), word.count > 3, word.hasSuffix("ches") || word.hasSuffix("shes") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), word.count > 2 {
            return String(word.dropLast())
        }
        return word
    }

    // MARK: - Serving-size parsing (Branded search results)

    struct ServingInfo: Equatable {
        var gramsPerServing: Double
        var count: Double        // household units per serving ("2 slices" → 2)
        var descriptor: String   // "slice"
        var rawText: String

        var gramsPerHouseholdUnit: Double { gramsPerServing / max(count, 1) }
    }

    static func servingInfo(for food: USDAFood) -> ServingInfo? {
        guard let size = food.servingSize, size > 0 else { return nil }
        let unit = (food.servingSizeUnit ?? "g").lowercased()
        let gramsPerServing: Double
        switch unit {
        case "g", "grm", "gram", "grams", "ml", "mlt": gramsPerServing = size
        case "oz": gramsPerServing = size * 28.35
        default: return nil
        }

        let raw = (food.householdServingFullText ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else {
            return ServingInfo(gramsPerServing: gramsPerServing, count: 1, descriptor: "serving", rawText: "serving")
        }
        let (count, descriptor) = parseHouseholdText(raw)
        return ServingInfo(gramsPerServing: gramsPerServing, count: count, descriptor: descriptor, rawText: raw)
    }

    /// "2 SLICES" → (2, "slice"); "1/4 cup" → (0.25, "cup"); "1 container" → (1, "container")
    static func parseHouseholdText(_ text: String) -> (count: Double, descriptor: String) {
        let lowered = text.lowercased()
        let scanner = Scanner(string: lowered)
        var count = 1.0
        if let first = scanner.scanDouble() {
            if scanner.scanString("/") != nil, let denominator = scanner.scanDouble(), denominator > 0 {
                count = first / denominator
            } else {
                count = first
            }
        }
        let rest = String(lowered[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
        let descriptor = singular(rest.components(separatedBy: .whitespaces).first ?? "serving")
        return (max(count, 0.001), descriptor.isEmpty ? "serving" : descriptor)
    }

    // MARK: - Grams resolution

    struct GramsResolution: Equatable {
        var grams: Double
        var isReliable: Bool
        var basis: String
    }

    static func resolveGrams(
        for request: FoodItemRequest,
        food: USDAFood,
        portions: [USDAPortion] = []
    ) -> GramsResolution {
        let quantity = request.quantity
        switch classifyUnit(request.unit) {
        case .weight(let grams):
            return GramsResolution(
                grams: quantity * grams, isReliable: true,
                basis: "\(quantity.formatted()) \(request.unit) = \(Int((quantity * grams).rounded())) g"
            )

        case .volume(let approxGrams):
            // A real USDA portion weight ("1 cup" = 158 g) beats water density.
            if let portion = portion(matching: request.unit, in: portions) {
                let perUnit = portion.gramWeight / max(portion.amount ?? 1, 0.001)
                return GramsResolution(
                    grams: quantity * perUnit, isReliable: true,
                    basis: "USDA portion '\(portion.label)' = \(Int(portion.gramWeight.rounded())) g"
                )
            }
            return GramsResolution(
                grams: quantity * approxGrams, isReliable: true,
                basis: "\(request.unit) ≈ \(Int(approxGrams)) g (water-density approximation)"
            )

        case .discrete(let word):
            if let info = servingInfo(for: food), isDiscreteWord(info.descriptor) {
                return GramsResolution(
                    grams: quantity * info.gramsPerHouseholdUnit, isReliable: true,
                    basis: "package serving '\(info.rawText)' → \(Int(info.gramsPerHouseholdUnit.rounded())) g per \(word)"
                )
            }
            if let portion = portion(matching: word, in: portions) ?? discretePortion(in: portions) {
                let perUnit = portion.gramWeight / max(portion.amount ?? 1, 0.001)
                return GramsResolution(
                    grams: quantity * perUnit, isReliable: true,
                    basis: "USDA portion '\(portion.label)' = \(Int(perUnit.rounded())) g per unit"
                )
            }
            // Deliberately NOT trusting 100 g for an inherently discrete item —
            // the value is a placeholder and the item is flagged for review.
            if let info = servingInfo(for: food) {
                return GramsResolution(
                    grams: quantity * info.gramsPerServing, isReliable: false,
                    basis: "no per-\(word) weight; guessed from serving size \(Int(info.gramsPerServing.rounded())) g"
                )
            }
            return GramsResolution(
                grams: quantity * 100, isReliable: false,
                basis: "no discrete-unit data; assumed 100 g per \(word) (needs review)"
            )

        case .serving:
            if let info = servingInfo(for: food) {
                return GramsResolution(
                    grams: quantity * info.gramsPerServing, isReliable: true,
                    basis: "package serving = \(Int(info.gramsPerServing.rounded())) g"
                )
            }
            if let portion = portions.first {
                return GramsResolution(
                    grams: quantity * portion.gramWeight, isReliable: true,
                    basis: "USDA portion '\(portion.label)' = \(Int(portion.gramWeight.rounded())) g"
                )
            }
            return GramsResolution(
                grams: quantity * 100, isReliable: false,
                basis: "no serving data; assumed 100 g per serving (needs review)"
            )

        case .vague(let word):
            // Vague amounts should have been resolved by a clarification card
            // before ever reaching a lookup. If one slips through ("keep as I
            // said it"), scale by a conservative single-portion guess — never
            // a bulk/family-size amount — and stay low confidence.
            let guess: Double
            switch word {
            case "bag": guess = 50
            case "bowl": guess = 240
            case "handful": guess = 40
            case "splash", "dash": guess = 5
            default: guess = 100 // some, bit, few, couple, little
            }
            return GramsResolution(
                grams: quantity * guess, isReliable: false,
                basis: "vague unit '\(word)' — unclarified; assumed \(Int(guess)) g (needs review)"
            )

        case .unknown:
            return GramsResolution(
                grams: quantity * 100, isReliable: false,
                basis: "unrecognized unit '\(request.unit)'; assumed 100 g (needs review)"
            )
        }
    }

    private static func portion(matching unitWord: String, in portions: [USDAPortion]) -> USDAPortion? {
        let target = singular(unitWord.lowercased())
        return portions.first { portion in
            tokens(portion.label).map(singular).contains(target)
        }
    }

    private static func discretePortion(in portions: [USDAPortion]) -> USDAPortion? {
        portions.first { portion in
            tokens(portion.label).map(singular).contains { discreteWords.contains($0) }
        }
    }

    // MARK: - Evaluation (scale + plausibility + confidence)

    static func evaluate(
        for request: FoodItemRequest,
        food: USDAFood,
        nameScore: Double,
        portions: [USDAPortion] = []
    ) -> (match: NutritionMatch, flags: [String], grams: GramsResolution) {
        let per100g = food.macrosPer100g
        let grams = resolveGrams(for: request, food: food, portions: portions)
        let factor = grams.grams / 100.0

        let calories = per100g.calories * factor
        let protein = per100g.protein * factor
        let carbs = per100g.carbs * factor
        let fat = per100g.fat * factor

        let flags = plausibilityFlags(
            calories: calories, protein: protein, carbs: carbs, fat: fat,
            grams: grams.grams, quantity: request.quantity,
            unitKind: classifyUnit(request.unit)
        )

        let confident = grams.isReliable && nameScore >= 0.5 && flags.isEmpty
        let match = NutritionMatch(
            matchedDescription: food.description,
            calories: calories, protein: protein, carbs: carbs, fat: fat,
            confidence: confident ? MatchConfidence.high : MatchConfidence.low
        )
        return (match, flags, grams)
    }

    /// Sanity checks that run after every match. Any flag forces
    /// matchConfidence = "low" so the item surfaces for manual review.
    static func plausibilityFlags(
        calories: Double, protein: Double, carbs: Double, fat: Double,
        grams: Double, quantity: Double, unitKind: UnitKind
    ) -> [String] {
        var flags: [String] = []

        // 1. Atwater consistency: calories should track 4P + 4C + 9F.
        let expected = protein * 4 + carbs * 4 + fat * 9
        if max(calories, expected) >= 25 {
            let deviation = abs(calories - expected) / max(expected, 1)
            if deviation > 0.15 {
                flags.append(String(format: "calories (%.0f) inconsistent with macros (expect ~%.0f)", calories, expected))
            }
        }

        // 2. Physical density bounds: nothing edible beats pure fat (~9 kcal/g),
        //    and macro mass can't exceed the food's own mass.
        if grams > 0 {
            if calories / grams > 9.2 {
                flags.append(String(format: "%.1f kcal/g exceeds any real food's energy density", calories / grams))
            }
            if protein + carbs + fat > grams * 1.05 {
                flags.append("macro grams exceed the food's total weight")
            }
        }

        // 3. Per-unit sanity bounds for discrete items — general size-category
        //    bounds, not per-food values. One thin slice/strip can't be 300 kcal.
        if case .discrete(let word) = unitKind {
            let perUnit = calories / max(quantity, 1)
            let bound = discreteCalorieBound(for: word)
            if perUnit > bound {
                flags.append(String(format: "%.0f kcal per %@ exceeds sanity bound (%.0f)", perUnit, word, bound))
            }
        }

        // 4. Vague units (bag, bowl, handful, some, ...) are single-portion
        //    words — a match that looks like a bulk/family-size amount is
        //    wrong regardless of which database entry produced it.
        if case .vague(let word) = unitKind {
            let perUnit = calories / max(quantity, 1)
            let bound = vagueCalorieBound(for: word)
            if perUnit > bound {
                flags.append(String(format: "%.0f kcal per %@ looks like a bulk amount (bound %.0f)", perUnit, word, bound))
            }
            flags.append("vague amount '\(word)' was never clarified")
        }

        return flags
    }

    /// Upper kcal bound for one vague-container portion.
    static func vagueCalorieBound(for word: String) -> Double {
        switch word {
        case "bag": return 350        // single-serve snack bag, not family size
        case "bowl": return 600
        case "handful": return 200
        case "splash", "dash": return 50
        default: return 400           // some, bit, few, couple, little
        }
    }

    /// Upper kcal bound for one unit, by rough physical size of the unit word.
    static func discreteCalorieBound(for word: String) -> Double {
        switch word {
        case "slice", "strip", "rasher", "small", "cookie", "meatball":
            return 200
        case "piece", "item", "each", "unit", "egg", "link", "stick", "patty", "pattie":
            return 350
        case "medium", "pancake", "waffle", "muffin", "roll", "bun", "tortilla", "bar", "sausage", "wing":
            return 400
        case "large", "whole", "bagel", "breast", "thigh", "filet", "fillet":
            return 500
        default:
            return 400
        }
    }

    /// Kept for the edit screen's manual swap flow.
    static func match(for request: FoodItemRequest, food: USDAFood, nameScore: Double) -> NutritionMatch {
        evaluate(for: request, food: food, nameScore: nameScore).match
    }

    // MARK: - Scoring

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

    // MARK: - Diagnostics

    static func candidateSummaries(for request: FoodItemRequest, in foods: [USDAFood]) -> [CandidateSummary] {
        foods.map { food in
            CandidateSummary(
                description: food.description,
                dataType: food.dataType ?? "?",
                nameScore: nameMatchScore(query: request.name, candidate: food.description),
                kcalPer100g: food.macrosPer100g.calories,
                serving: servingInfo(for: food).map { "\($0.rawText) = \(Int($0.gramsPerServing.rounded())) g" }
            )
        }
    }

    @MainActor
    private static func record(_ diagnostics: MatchDiagnostics) {
        MatchDebugLog.shared.record(diagnostics)
    }
}

// MARK: - USDA FoodData Central wire types

struct USDASearchResponse: Decodable {
    let foods: [USDAFood]
}

struct USDAFood: Codable, Identifiable, Equatable {
    struct Nutrient: Codable, Equatable {
        let nutrientId: Int
        let nutrientName: String?
        let unitName: String?
        let value: Double?
    }

    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let brandName: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let householdServingFullText: String?
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

/// One entry of a detail record's foodPortions array.
struct USDAPortion: Decodable, Equatable {
    struct MeasureUnit: Decodable, Equatable {
        let name: String?
    }

    let amount: Double?
    let gramWeight: Double
    let modifier: String?
    let portionDescription: String?
    let measureUnit: MeasureUnit?

    /// Human-readable portion label, whichever field the data type populated.
    var label: String {
        let parts = [portionDescription, modifier, measureUnit?.name]
        return parts.compactMap { $0 }.first { !$0.isEmpty && $0.lowercased() != "undetermined" } ?? "portion"
    }
}

struct USDAFoodDetail: Decodable {
    let foodPortions: [USDAPortion]?
}
