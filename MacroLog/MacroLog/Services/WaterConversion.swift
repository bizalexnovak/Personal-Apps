import Foundation

/// Water is tracked separately from macros, in fluid ounces. This converts a
/// logged water item's quantity/unit ("1 bottle", "500 ml", "2 glasses") into
/// ounces for the daily tally.
enum WaterConversion {
    /// True when a food item is (plain) water. "watermelon" tokenizes to one
    /// word so it won't match; "water"/"sparkling water"/"ice water" do.
    static func isWater(_ name: String) -> Bool {
        let tokens = Set(
            name.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
        )
        return tokens.contains("water") && !tokens.contains("melon")
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
        let u = unit.lowercased().trimmingCharacters(in: .whitespaces)
        return quantity * (perUnit[u] ?? 8)
    }

    /// Ounces contributed by one saved item — 0 unless it's water.
    static func ounces(for item: FoodItem) -> Double {
        isWater(item.name) ? ounces(quantity: item.quantity, unit: item.unit) : 0
    }
}

/// Zero-calorie supplements logged directly ("5 g of creatine", "a caffeine
/// pill") — like water, these skip USDA entirely: a food search would match
/// them to nonsense, and their value lives in the micronutrient record.
enum SupplementConversion {
    private static func tokens(_ name: String) -> Set<String> {
        Set(name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }

    /// A ready-made match when the item is a bare supplement, else nil.
    static func match(for request: FoodItemRequest) -> NutritionMatch? {
        let words = tokens(request.name)
        if words.contains("creatine") {
            let grams = creatineGrams(quantity: request.quantity, unit: request.unit)
            var micros = Micronutrients()
            micros.creatine = grams
            return NutritionMatch(
                matchedDescription: "Creatine · \(trimmed(grams)) g",
                calories: 0, protein: 0, carbs: 0, fat: 0,
                confidence: MatchConfidence.high,
                micros: micros
            )
        }
        // "caffeine pill"/"200 mg of caffeine" — but not e.g. "caffeine-free coke".
        if words.contains("caffeine"), !words.contains("free") {
            let mg = caffeineMilligrams(quantity: request.quantity, unit: request.unit)
            var micros = Micronutrients()
            micros.caffeine = mg
            return NutritionMatch(
                matchedDescription: "Caffeine · \(trimmed(mg)) mg",
                calories: 0, protein: 0, carbs: 0, fat: 0,
                confidence: MatchConfidence.high,
                micros: micros
            )
        }
        return nil
    }

    /// Grams of creatine for a quantity + unit. A scoop/serving is the common
    /// 5 g dose; unknown units also default to 5 g each.
    static func creatineGrams(quantity: Double, unit: String) -> Double {
        switch normalized(unit) {
        case "g", "gram", "grams": return quantity
        case "mg", "milligram", "milligrams": return quantity / 1000
        default: return quantity * 5 // scoop, serving, dose…
        }
    }

    /// Milligrams of caffeine for a quantity + unit. Pills/tablets default to
    /// the common 200 mg dose; unknown units too.
    static func caffeineMilligrams(quantity: Double, unit: String) -> Double {
        switch normalized(unit) {
        case "mg", "milligram", "milligrams": return quantity
        case "g", "gram", "grams": return quantity * 1000
        default: return quantity * 200 // pill, tablet, capsule, serving…
        }
    }

    private static func normalized(_ unit: String) -> String {
        unit.lowercased().trimmingCharacters(in: .whitespaces)
    }

    private static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
