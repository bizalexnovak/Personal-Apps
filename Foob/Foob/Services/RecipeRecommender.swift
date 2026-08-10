import Foundation

/// The user's macro goals for the day. Nil-able at the call site: if no goals
/// are set the macro-gap term is skipped and the recommender leans purely on
/// time of day and past preference.
struct MacroTargets: Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

/// What's already been logged today. At the start of the day this is all
/// zeros, which the recommender reads as "every macro is wide open" — so the
/// macro term is uniform and time-of-day decides.
struct DayIntake: Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let none = DayIntake(calories: 0, protein: 0, carbs: 0, fat: 0)

    /// Any food logged yet today? Used to decide whether to mention macro gaps
    /// in the reason line (there's nothing to "fill" before you've eaten).
    var hasIntake: Bool { calories > 0 || protein > 0 || carbs > 0 || fat > 0 }
}

/// A recipe the engine is suggesting right now, with why.
struct RecipeRecommendation: Identifiable {
    let recipe: Recipe
    let score: Double
    /// Short human explanation shown as a chip, e.g. "Dinner · high protein".
    let reason: String

    var id: UUID { recipe.id }
}

/// Ranks saved recipes for "what should I make right now", combining three
/// signals the user asked for:
///   1. Time of day — breakfast-y recipes in the morning, dinners at night.
///   2. Macro gaps — as the day fills in, favour recipes heavy in whatever
///      macro is furthest from its goal (short on protein → protein-heavy).
///   3. Preference — recipes logged often (and recently) drift up over time.
/// Pure and deterministic (time is passed in) so it's straightforward to test.
enum RecipeRecommender {
    // Relative weights of the three signals. Macro fit is weighted a touch
    // above time so a strong gap can override the time-of-day default once the
    // day is underway; preference is a gentle nudge, not a dictator.
    private static let timeWeight = 1.0
    private static let macroWeight = 1.3
    private static let prefWeight = 0.6

    static func recommend(
        recipes: [Recipe],
        targets: MacroTargets?,
        intake: DayIntake,
        now: Date = .now,
        calendar: Calendar = .current,
        limit: Int = 4
    ) -> [RecipeRecommendation] {
        // Empty recipes (no ingredients / no calories) can't be a meal.
        let candidates = recipes.filter { $0.totalCalories > 0 && !$0.ingredientList.isEmpty }
        guard !candidates.isEmpty else { return [] }

        let slot = MealSlot.current(now, calendar: calendar)
        let weights = macroWeights(targets: targets, intake: intake)
        let caloriesRemaining = targets.map { max(0, $0.calories - intake.calories) }

        let scored = candidates.map { recipe -> RecipeRecommendation in
            let time = timeScore(recipe: recipe, slot: slot)
            let macro = macroScore(recipe: recipe, weights: weights)
            let pref = preferenceScore(recipe: recipe, now: now)

            var score = timeWeight * time + macroWeight * macro + prefWeight * pref
            // Don't push a 900 kcal dinner when only a snack's worth of
            // calories is left — only once some intake makes "remaining" real.
            if let remaining = caloriesRemaining, intake.hasIntake, remaining > 0,
               recipe.totalCalories > remaining * 1.3 {
                score *= 0.6
            }

            return RecipeRecommendation(
                recipe: recipe,
                score: score,
                reason: reason(recipe: recipe, slot: slot, weights: weights, intake: intake)
            )
        }

        return scored
            .sorted {
                $0.score != $1.score
                    ? $0.score > $1.score
                    : $0.recipe.name < $1.recipe.name // stable tiebreak
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Signals

    /// 1.0 when the recipe's slot matches the current one, a middling score for
    /// "any time" recipes, and a low score for a clearly out-of-time recipe.
    private static func timeScore(recipe: Recipe, slot: MealSlot) -> Double {
        if recipe.slot == slot { return 1.0 }
        if recipe.slot == .any { return 0.6 }
        return 0.25
    }

    /// Per-macro weights in [0,1] that sum to 1, reflecting how far each macro
    /// is from its goal (fraction remaining). All-equal (⅓ each) at the start
    /// of the day or when no targets are set, so the macro term doesn't bias
    /// anything until there's a real gap to chase.
    private static func macroWeights(targets: MacroTargets?, intake: DayIntake) -> (protein: Double, carbs: Double, fat: Double) {
        guard let targets else { return (1.0 / 3, 1.0 / 3, 1.0 / 3) }
        func fractionRemaining(_ consumed: Double, _ target: Double) -> Double {
            guard target > 0 else { return 0 }
            return min(1, max(0, (target - consumed) / target))
        }
        let p = fractionRemaining(intake.protein, targets.protein)
        let c = fractionRemaining(intake.carbs, targets.carbs)
        let f = fractionRemaining(intake.fat, targets.fat)
        let sum = p + c + f
        guard sum > 0 else { return (1.0 / 3, 1.0 / 3, 1.0 / 3) } // all goals met
        return (p / sum, c / sum, f / sum)
    }

    /// How well the recipe's macro *composition* lines up with where the gaps
    /// are. A recipe that gets most of its calories from protein scores high
    /// when protein is the macro furthest from goal. In [0,1].
    private static func macroScore(recipe: Recipe, weights: (protein: Double, carbs: Double, fat: Double)) -> Double {
        let shares = macroShares(recipe: recipe)
        return shares.protein * weights.protein
            + shares.carbs * weights.carbs
            + shares.fat * weights.fat
    }

    /// Fraction of the recipe's macro calories coming from each macro
    /// (protein/carbs 4 kcal/g, fat 9 kcal/g). Sums to 1.
    private static func macroShares(recipe: Recipe) -> (protein: Double, carbs: Double, fat: Double) {
        let p = recipe.totalProtein * 4
        let c = recipe.totalCarbs * 4
        let f = recipe.totalFat * 9
        let total = p + c + f
        guard total > 0 else { return (1.0 / 3, 1.0 / 3, 1.0 / 3) }
        return (p / total, c / total, f / total)
    }

    /// Grows toward 1 as a recipe is logged more often, with a small recency
    /// bump for ones used in the last two weeks — this is what lets the list
    /// "get a feel" for the user's favourites over time.
    private static func preferenceScore(recipe: Recipe, now: Date) -> Double {
        let frequency = min(1.0, Double(recipe.timesLogged) / 5.0)
        var recency = 0.0
        if let last = recipe.lastLoggedAt {
            let days = now.timeIntervalSince(last) / 86_400
            if days < 14 { recency = 0.2 * (1 - days / 14) }
        }
        return min(1.0, frequency + recency)
    }

    // MARK: - Reason line

    private static func reason(
        recipe: Recipe, slot: MealSlot,
        weights: (protein: Double, carbs: Double, fat: Double),
        intake: DayIntake
    ) -> String {
        var parts: [String] = []
        if recipe.slot == slot {
            parts.append(slot.label)
        } else if recipe.timesLogged >= 3 {
            parts.append("Favourite")
        }

        // Mention a macro only once the day is underway and one gap clearly
        // leads — and only if this recipe actually delivers that macro.
        if intake.hasIntake {
            let shares = macroShares(recipe: recipe)
            let ranked = [
                ("protein", weights.protein, shares.protein),
                ("carbs", weights.carbs, shares.carbs),
                ("fat", weights.fat, shares.fat),
            ].sorted { $0.1 > $1.1 }
            if let top = ranked.first, top.1 > 0.4, top.2 >= 0.33 {
                parts.append("high \(top.0)")
            }
        }

        if parts.isEmpty { parts.append(recipe.slot == .any ? "Any time" : recipe.slot.label) }
        return parts.joined(separator: " · ")
    }
}
