import Foundation

enum BiologicalSex: String, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var title: String { self == .male ? "Male" : "Female" }
}

enum ActivityLevel: String, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light: return "Lightly active"
        case .moderate: return "Moderately active"
        case .active: return "Active"
        case .veryActive: return "Very active"
        }
    }
    /// TDEE multiplier applied to BMR.
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

enum GoalType: String, CaseIterable, Identifiable {
    case lose, maintain, gain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lose: return "Lose"
        case .maintain: return "Maintain"
        case .gain: return "Gain"
        }
    }
    /// Daily calorie delta from maintenance.
    var calorieAdjustment: Double {
        switch self {
        case .lose: return -500
        case .maintain: return 0
        case .gain: return 300
        }
    }
}

struct RecommendedGoals: Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var waterOunces: Double
}

/// Derives maintenance-based daily targets from body metrics using the
/// Mifflin-St Jeor equation (the current standard for BMR estimation).
enum GoalCalculator {
    /// Basal metabolic rate (kcal/day).
    static func bmr(sex: BiologicalSex, heightInches: Double, weightPounds: Double, ageYears: Double) -> Double {
        let kg = weightPounds * 0.453592
        let cm = heightInches * 2.54
        let base = 10 * kg + 6.25 * cm - 5 * ageYears
        return sex == .male ? base + 5 : base - 161
    }

    /// Total daily energy expenditure = BMR × activity multiplier. This is the
    /// number of calories to maintain current weight.
    static func maintenanceCalories(
        sex: BiologicalSex, heightInches: Double, weightPounds: Double,
        ageYears: Double, activity: ActivityLevel
    ) -> Double {
        bmr(sex: sex, heightInches: heightInches, weightPounds: weightPounds, ageYears: ageYears) * activity.multiplier
    }

    /// Full recommended goals, or nil if body metrics aren't entered yet.
    /// Macros use a 30% protein / 40% carbs / 30% fat split of the goal
    /// calories; water is half body weight in ounces (min 64 oz).
    static func recommended(
        sex: BiologicalSex, heightInches: Double, weightPounds: Double,
        ageYears: Double, activity: ActivityLevel, goal: GoalType
    ) -> RecommendedGoals? {
        guard heightInches > 0, weightPounds > 0, ageYears > 0 else { return nil }
        let maintenance = maintenanceCalories(
            sex: sex, heightInches: heightInches, weightPounds: weightPounds,
            ageYears: ageYears, activity: activity
        )
        let calories = max(1200, maintenance + goal.calorieAdjustment) // safe floor
        return RecommendedGoals(
            calories: calories.rounded(),
            protein: (calories * 0.30 / 4).rounded(),
            carbs: (calories * 0.40 / 4).rounded(),
            fat: (calories * 0.30 / 9).rounded(),
            waterOunces: max(64, weightPounds * 0.5).rounded()
        )
    }
}
