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
    /// How far (in clock hours, wrapping midnight) a past log can be from the
    /// current time and still count as "around now" for ranking.
    static let nearNowWindowHours = 2

    /// Build suggestions from logged history: group by food (name + unit,
    /// ignoring quantity so "2 eggs" and "3 eggs" count as the same food) and
    /// keep only real repeats (logged ≥ 2 times, across any days).
    ///
    /// Ranking is time-of-day aware: each logging within ±2 h of the current
    /// clock time counts double on top of overall frequency, so at 7 AM the
    /// strip leads with your usual breakfasts and at 9 PM with your usual
    /// snacks. Ties break by total count, then recency. `meals` should be
    /// newest-first so the first item seen per group is the most recent — its
    /// quantity/macros become the one-tap re-log values.
    static func compute(from meals: [Meal], limit: Int = 6, now: Date = .now) -> [MealSuggestion] {
        struct Bucket {
            var suggestion: MealSuggestion
            var lastSeen: Date
            var nearNowCount = 0
            var score: Int { suggestion.count + 2 * nearNowCount }
        }
        let cal = Calendar.current
        let nowHour = cal.component(.hour, from: now)
        var buckets: [String: Bucket] = [:]

        for meal in meals {
            let hour = cal.component(.hour, from: meal.timestamp)
            let nearNow = circularHourDistance(hour, nowHour) <= nearNowWindowHours
            for item in meal.items {
                let name = item.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let key = "\(name.lowercased())|\(item.unit.lowercased())"
                if var existing = buckets[key] {
                    existing.suggestion.count += 1
                    if nearNow { existing.nearNowCount += 1 }
                    buckets[key] = existing
                } else {
                    buckets[key] = Bucket(
                        suggestion: MealSuggestion(
                            id: key, name: name, quantity: item.quantity, unit: item.unit,
                            calories: item.calories, protein: item.protein,
                            carbs: item.carbs, fat: item.fat, micros: item.micros, count: 1
                        ),
                        lastSeen: meal.timestamp,
                        nearNowCount: nearNow ? 1 : 0
                    )
                }
            }
        }

        return buckets.values
            .filter { $0.suggestion.count >= 2 }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.suggestion.count != $1.suggestion.count {
                    return $0.suggestion.count > $1.suggestion.count
                }
                return $0.lastSeen > $1.lastSeen
            }
            .prefix(limit)
            .map(\.suggestion)
    }

    /// Hours apart on a 24-hour clock, wrapping midnight (23 vs 1 → 2).
    static func circularHourDistance(_ a: Int, _ b: Int) -> Int {
        let direct = abs(a - b)
        return min(direct, 24 - direct)
    }
}
