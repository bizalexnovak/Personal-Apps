import Foundation

/// Per-entry micronutrient detail beyond the four headline macros: the fat and
/// carb breakdowns plus common minerals and vitamins. Every field is optional
/// so "not recorded" stays distinct from a real zero. Values are for the item's
/// logged portion (already scaled), matching how calories/protein/etc. are stored.
///
/// Not shown on Home or the Trends chart — recorded with each entry and viewable
/// in the meal editor. Stored on `FoodItem` as JSON so new fields can be added
/// later without a SwiftData schema migration.
struct Micronutrients: Codable, Equatable, Hashable {
    // Fat breakdown (g)
    var saturatedFat: Double?
    var transFat: Double?
    var monounsaturatedFat: Double?
    var polyunsaturatedFat: Double?
    // Carb breakdown (g)
    var fiber: Double?
    var totalSugars: Double?
    var addedSugars: Double?
    // Sterols & electrolytes (mg)
    var cholesterol: Double?
    var sodium: Double?
    var potassium: Double?
    // Minerals (mg unless noted)
    var calcium: Double?
    var iron: Double?
    var magnesium: Double?
    var zinc: Double?
    var phosphorus: Double?
    var copper: Double?
    var manganese: Double?
    var selenium: Double?  // mcg
    // Vitamins
    var vitaminA: Double?   // mcg RAE
    var vitaminC: Double?   // mg
    var vitaminD: Double?   // mcg
    var vitaminE: Double?   // mg
    var vitaminK: Double?   // mcg
    var thiamin: Double?    // B1, mg
    var riboflavin: Double? // B2, mg
    var niacin: Double?     // B3, mg
    var vitaminB6: Double?  // mg
    var folate: Double?     // mcg
    var vitaminB12: Double? // mcg
    // Stimulants & supplements
    var caffeine: Double?   // mg
    var creatine: Double?   // g — not in USDA data; captured from supplement
                            // labels or logged directly ("5 g of creatine")

    static let empty = Micronutrients()

    var isEmpty: Bool { Self.fields.allSatisfy { self[keyPath: $0.keyPath] == nil } }

    /// Field-wise sum, for daily totals: a value recorded on either side is
    /// added (nil = 0 there); fields recorded on neither side stay nil.
    func adding(_ other: Micronutrients) -> Micronutrients {
        var copy = self
        for field in Self.fields {
            if let value = other[keyPath: field.keyPath] {
                copy[keyPath: field.keyPath] = (copy[keyPath: field.keyPath] ?? 0) + value
            }
        }
        return copy
    }

    /// Scale every recorded value by a factor (portion changes), leaving
    /// unrecorded (nil) fields nil.
    func scaled(by factor: Double) -> Micronutrients {
        var copy = self
        for field in Self.fields {
            if let value = copy[keyPath: field.keyPath] {
                copy[keyPath: field.keyPath] = value * factor
            }
        }
        return copy
    }

    /// Recorded fields in display order, for the meal editor's read-out.
    var recorded: [(label: String, value: Double, unit: String)] {
        Self.fields.compactMap { field in
            guard let value = self[keyPath: field.keyPath] else { return nil }
            return (field.label, value, field.unit)
        }
    }
}

/// Describes one micronutrient: how to display it and where to find it in USDA
/// FoodData Central (nutrient numbers, first match wins). One list drives both
/// USDA extraction and the editor read-out so they never drift apart.
struct MicronutrientField {
    let label: String
    let unit: String
    let keyPath: WritableKeyPath<Micronutrients, Double?>
    /// FDC nutrient numbers, in preference order.
    let usdaIDs: [Int]
}

extension Micronutrients {
    static let fields: [MicronutrientField] = [
        .init(label: "Saturated fat", unit: "g", keyPath: \.saturatedFat, usdaIDs: [1258]),
        .init(label: "Trans fat", unit: "g", keyPath: \.transFat, usdaIDs: [1257]),
        .init(label: "Monounsaturated fat", unit: "g", keyPath: \.monounsaturatedFat, usdaIDs: [1292]),
        .init(label: "Polyunsaturated fat", unit: "g", keyPath: \.polyunsaturatedFat, usdaIDs: [1293]),
        .init(label: "Fiber", unit: "g", keyPath: \.fiber, usdaIDs: [1079, 2033]),
        .init(label: "Total sugars", unit: "g", keyPath: \.totalSugars, usdaIDs: [2000, 1063]),
        .init(label: "Added sugars", unit: "g", keyPath: \.addedSugars, usdaIDs: [1235]),
        .init(label: "Cholesterol", unit: "mg", keyPath: \.cholesterol, usdaIDs: [1253]),
        .init(label: "Sodium", unit: "mg", keyPath: \.sodium, usdaIDs: [1093]),
        .init(label: "Potassium", unit: "mg", keyPath: \.potassium, usdaIDs: [1092]),
        .init(label: "Calcium", unit: "mg", keyPath: \.calcium, usdaIDs: [1087]),
        .init(label: "Iron", unit: "mg", keyPath: \.iron, usdaIDs: [1089]),
        .init(label: "Magnesium", unit: "mg", keyPath: \.magnesium, usdaIDs: [1090]),
        .init(label: "Zinc", unit: "mg", keyPath: \.zinc, usdaIDs: [1095]),
        .init(label: "Phosphorus", unit: "mg", keyPath: \.phosphorus, usdaIDs: [1091]),
        .init(label: "Copper", unit: "mg", keyPath: \.copper, usdaIDs: [1098]),
        .init(label: "Manganese", unit: "mg", keyPath: \.manganese, usdaIDs: [1101]),
        .init(label: "Selenium", unit: "mcg", keyPath: \.selenium, usdaIDs: [1103]),
        .init(label: "Vitamin A", unit: "mcg", keyPath: \.vitaminA, usdaIDs: [1106]),
        .init(label: "Vitamin C", unit: "mg", keyPath: \.vitaminC, usdaIDs: [1162]),
        .init(label: "Vitamin D", unit: "mcg", keyPath: \.vitaminD, usdaIDs: [1114]),
        .init(label: "Vitamin E", unit: "mg", keyPath: \.vitaminE, usdaIDs: [1109]),
        .init(label: "Vitamin K", unit: "mcg", keyPath: \.vitaminK, usdaIDs: [1185]),
        .init(label: "Thiamin (B1)", unit: "mg", keyPath: \.thiamin, usdaIDs: [1165]),
        .init(label: "Riboflavin (B2)", unit: "mg", keyPath: \.riboflavin, usdaIDs: [1166]),
        .init(label: "Niacin (B3)", unit: "mg", keyPath: \.niacin, usdaIDs: [1167]),
        .init(label: "Vitamin B6", unit: "mg", keyPath: \.vitaminB6, usdaIDs: [1175]),
        .init(label: "Folate", unit: "mcg", keyPath: \.folate, usdaIDs: [1190, 1177]),
        .init(label: "Vitamin B12", unit: "mcg", keyPath: \.vitaminB12, usdaIDs: [1178]),
        .init(label: "Caffeine", unit: "mg", keyPath: \.caffeine, usdaIDs: [1057]),
        // No FDC nutrient number — creatine comes from labels or direct logging.
        .init(label: "Creatine", unit: "g", keyPath: \.creatine, usdaIDs: []),
    ]
}
