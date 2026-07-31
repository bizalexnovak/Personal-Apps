import Foundation

/// Shared word-tokenization for name sniffing ("is this water?", "is this a
/// bare supplement?") so the two detectors can never drift apart.
enum NameTokens {
    static func tokens(_ name: String) -> Set<String> {
        Set(
            name.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
        )
    }

    /// Lowercased, whitespace-trimmed unit keyword for table lookups.
    static func normalizedUnit(_ unit: String) -> String {
        unit.lowercased().trimmingCharacters(in: .whitespaces)
    }
}

/// Water is tracked separately from macros, in fluid ounces. This converts a
/// logged water item's quantity/unit ("1 bottle", "500 ml", "2 glasses") into
/// ounces for the daily tally.
enum WaterConversion {
    /// True when a food item is (plain) water. "watermelon" tokenizes to one
    /// word so it won't match; "water"/"sparkling water"/"ice water" do.
    /// Caffeinated waters are excluded — they're real products with a caffeine
    /// content, so they go through the USDA lookup (which carries caffeine)
    /// instead of the plain-water shortcut that would discard it.
    static func isWater(_ name: String) -> Bool {
        let tokens = NameTokens.tokens(name)
        return tokens.contains("water")
            && !tokens.contains("melon")
            && !tokens.contains("caffeine")
            && !tokens.contains("caffeinated")
    }

    /// Ounces per unit keyword. Built once — this lookup runs per item in every
    /// day/trend aggregation pass.
    private static let perUnit: [String: Double] = [
        "oz": 1, "ounce": 1, "ounces": 1,
        "fl oz": 1, "floz": 1, "fluid ounce": 1, "fluid ounces": 1,
        "ml": 0.033814, "milliliter": 0.033814, "milliliters": 0.033814,
        "l": 33.814, "liter": 33.814, "liters": 33.814, "litre": 33.814, "litres": 33.814,
        "cup": 8, "cups": 8,
        "glass": 8, "glasses": 8,
        "bottle": 16, "bottles": 16,              // default bottle size
        "can": 12, "cans": 12,
        "pint": 16, "pints": 16,
        "quart": 32, "quarts": 32,
        "gallon": 128, "gallons": 128,
    ]

    /// Fluid ounces for a quantity + volume unit. Unknown units fall back to a
    /// single glass (8 oz), a reasonable single serving.
    static func ounces(quantity: Double, unit: String) -> Double {
        quantity * (perUnit[NameTokens.normalizedUnit(unit)] ?? 8)
    }

    /// Ounces contributed by one saved item — 0 unless it's water.
    static func ounces(for item: FoodItem) -> Double {
        isWater(item.name) ? ounces(quantity: item.quantity, unit: item.unit) : 0
    }
}

/// Zero-calorie supplements logged directly ("5 g of creatine", "a caffeine
/// pill", "6 grams of citrulline") — like water, these skip USDA entirely: a
/// food search would match them to nonsense, and their value lives in the
/// micronutrient record.
enum SupplementConversion {
    /// How a supplement's dose is stored on `Micronutrients`.
    private enum DoseUnit {
        case grams, milligrams

        var displayUnit: String {
            switch self {
            case .grams: return "g"
            case .milligrams: return "mg"
            }
        }
    }

    /// One directly-loggable supplement. The name must contain every
    /// `required` token and nothing outside `allowed` — anything else in the
    /// name ("creatine gummies", "creatine protein blend") means a real
    /// caloric product that must go through the normal lookup so its calories
    /// aren't zeroed.
    ///
    /// Deliberate trade-off: branded phrasings ("Optimum Nutrition creatine")
    /// also fall through to USDA rather than dose-guessing here — brand words
    /// are unbounded, and a wrong zero-calorie guess is worse than a lookup.
    /// Say the bare name ("5 grams of creatine") for direct dose logging.
    private struct BareSupplement {
        let required: Set<String>
        let allowed: Set<String>
        let storage: DoseUnit
        let keyPath: WritableKeyPath<Micronutrients, Double?>
        /// Dose per scoop/pill/serving (in the storage unit) when the unit
        /// isn't an explicit weight.
        let defaultDose: Double
        let displayName: String
    }

    /// Checked in order; creatine and caffeine first (the originals).
    /// "l" is allowed where dictation may produce "L-theanine" → {l, theanine}.
    private static let supplements: [BareSupplement] = [
        .init(required: ["creatine"],
              allowed: ["creatine", "monohydrate", "micronized", "powder", "supplement",
                        "scoop", "scoops", "unflavored", "unflavoured", "hcl"],
              storage: .grams, keyPath: \.creatine, defaultDose: 5,
              displayName: "Creatine"),
        .init(required: ["caffeine"],
              allowed: ["caffeine", "anhydrous", "pill", "pills", "tablet", "tablets",
                        "capsule", "capsules", "supplement"],
              storage: .milligrams, keyPath: \.caffeine, defaultDose: 200,
              displayName: "Caffeine"),
        .init(required: ["citrulline"],
              allowed: ["citrulline", "l", "malate", "powder", "supplement",
                        "scoop", "scoops", "unflavored", "unflavoured"],
              storage: .grams, keyPath: \.citrulline, defaultDose: 6,
              displayName: "L-Citrulline"),
        .init(required: ["beta", "alanine"],
              allowed: ["beta", "alanine", "powder", "supplement",
                        "scoop", "scoops", "unflavored", "unflavoured"],
              storage: .grams, keyPath: \.betaAlanine, defaultDose: 3.2,
              displayName: "Beta-alanine"),
        .init(required: ["betaine"],
              allowed: ["betaine", "anhydrous", "trimethylglycine", "powder",
                        "supplement", "scoop", "scoops"],
              storage: .grams, keyPath: \.betaine, defaultDose: 2.5,
              displayName: "Betaine"),
        .init(required: ["taurine"],
              allowed: ["taurine", "l", "powder", "supplement", "scoop", "scoops",
                        "pill", "pills", "tablet", "tablets", "capsule", "capsules"],
              storage: .milligrams, keyPath: \.taurine, defaultDose: 1000,
              displayName: "Taurine"),
        .init(required: ["tyrosine"],
              allowed: ["tyrosine", "l", "n", "acetyl", "powder", "supplement",
                        "scoop", "scoops", "pill", "pills", "tablet", "tablets",
                        "capsule", "capsules"],
              storage: .milligrams, keyPath: \.tyrosine, defaultDose: 500,
              displayName: "L-Tyrosine"),
        .init(required: ["theanine"],
              allowed: ["theanine", "l", "supplement", "pill", "pills",
                        "tablet", "tablets", "capsule", "capsules"],
              storage: .milligrams, keyPath: \.theanine, defaultDose: 200,
              displayName: "L-Theanine"),
        .init(required: ["alpha", "gpc"],
              allowed: ["alpha", "gpc", "powder", "supplement", "pill", "pills",
                        "tablet", "tablets", "capsule", "capsules"],
              storage: .milligrams, keyPath: \.alphaGPC, defaultDose: 300,
              displayName: "Alpha-GPC"),
    ]

    /// A ready-made match when the item is a bare supplement, else nil.
    /// The name must contain the supplement's tokens and nothing outside its
    /// allowed vocabulary, and the dose must be positive.
    static func match(for request: FoodItemRequest) -> NutritionMatch? {
        let words = NameTokens.tokens(request.name)
        for supplement in supplements {
            guard supplement.required.isSubset(of: words),
                  words.isSubset(of: supplement.allowed) else { continue }
            let amount = dose(
                quantity: request.quantity, unit: request.unit,
                storage: supplement.storage, defaultPerUnit: supplement.defaultDose
            )
            guard amount > 0 else { return nil }
            var micros = Micronutrients()
            micros[keyPath: supplement.keyPath] = amount
            return NutritionMatch(
                matchedDescription: "\(supplement.displayName) · \(PortionScale.numberText(amount)) \(supplement.storage.displayUnit)",
                calories: 0, protein: 0, carbs: 0, fat: 0,
                confidence: MatchConfidence.high,
                micros: micros
            )
        }
        return nil
    }

    /// Convert a spoken quantity + unit into the storage unit. Explicit
    /// weights convert exactly; anything else (scoop, pill, serving, dose…)
    /// counts as `defaultPerUnit` each.
    private static func dose(
        quantity: Double, unit: String, storage: DoseUnit, defaultPerUnit: Double
    ) -> Double {
        let u = NameTokens.normalizedUnit(unit)
        let isGrams = u == "g" || u == "gram" || u == "grams"
        let isMilligrams = u == "mg" || u == "milligram" || u == "milligrams"
        switch storage {
        case .grams:
            if isGrams { return quantity }
            if isMilligrams { return quantity / 1000 }
        case .milligrams:
            if isMilligrams { return quantity }
            if isGrams { return quantity * 1000 }
        }
        return quantity * defaultPerUnit
    }

    /// Grams of creatine for a quantity + unit. A scoop/serving is the common
    /// 5 g dose; unknown units also default to 5 g each.
    static func creatineGrams(quantity: Double, unit: String) -> Double {
        dose(quantity: quantity, unit: unit, storage: .grams, defaultPerUnit: 5)
    }

    /// Milligrams of caffeine for a quantity + unit. Pills/tablets default to
    /// the common 200 mg dose; unknown units too.
    static func caffeineMilligrams(quantity: Double, unit: String) -> Double {
        dose(quantity: quantity, unit: unit, storage: .milligrams, defaultPerUnit: 200)
    }
}
