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

    /// Fluid ounces for a quantity + volume unit. Unknown units fall back to a
    /// single glass (8 oz), a reasonable single serving.
    static func ounces(quantity: Double, unit: String) -> Double {
        let u = unit.lowercased().trimmingCharacters(in: .whitespaces)
        let perUnit: [String: Double] = [
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
        return quantity * (perUnit[u] ?? 8)
    }

    /// Ounces contributed by one saved item — 0 unless it's water.
    static func ounces(for item: FoodItem) -> Double {
        isWater(item.name) ? ounces(quantity: item.quantity, unit: item.unit) : 0
    }
}
