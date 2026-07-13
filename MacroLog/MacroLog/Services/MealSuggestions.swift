import Foundation

/// A frequently-logged item offered for one-tap re-logging (e.g. "24 oz water",
/// "Chobani greek yogurt"). Carries the last-known macros so tapping it logs a
/// copy immediately without re-running parsing or lookup.
struct MealSuggestion: Identifiable, Equatable {
    let id: String            // normalized key
    var name: String
    var quantity: Double
    var unit: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var micros: Micronutrients
    var count: Int

    /// "24 oz water" / "2 serving Chobani greek yogurt" style label.
    var label: String {
        let qty = quantity == quantity.rounded() ? "\(Int(quantity))" : quantity.formatted()
        return "\(qty) \(unit) \(name)"
    }
}

enum MealSuggestions {
    /// Build suggestions from logged history: group by food (name + unit,
    /// ignoring quantity so "2 eggs" and "3 eggs" count as the same food),
    /// keep only real repeats (logged ≥ 2 times, across any days), and rank by
    /// how often they appear, then recency. `meals` should be newest-first so
    /// the first item seen per group is the most recent — its quantity/macros
    /// become the one-tap re-log values.
    static func compute(from meals: [Meal], limit: Int = 6) -> [MealSuggestion] {
        struct Bucket { var suggestion: MealSuggestion; var lastSeen: Date }
        var buckets: [String: Bucket] = [:]

        for meal in meals {
            for item in meal.items {
                let name = item.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let key = "\(name.lowercased())|\(item.unit.lowercased())"
                if var existing = buckets[key] {
                    existing.suggestion.count += 1
                    buckets[key] = existing
                } else {
                    buckets[key] = Bucket(
                        suggestion: MealSuggestion(
                            id: key, name: name, quantity: item.quantity, unit: item.unit,
                            calories: item.calories, protein: item.protein,
                            carbs: item.carbs, fat: item.fat, micros: item.micros, count: 1
                        ),
                        lastSeen: meal.timestamp
                    )
                }
            }
        }

        return buckets.values
            .filter { $0.suggestion.count >= 2 }
            .sorted {
                $0.suggestion.count != $1.suggestion.count
                    ? $0.suggestion.count > $1.suggestion.count
                    : $0.lastSeen > $1.lastSeen
            }
            .prefix(limit)
            .map(\.suggestion)
    }
}
