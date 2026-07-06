import AppIntents
import SwiftData

/// "Log meal in MacroLog" — Siri collects the meal description, the intent runs
/// the full parse → lookup → save pipeline in the background (no app launch),
/// and Siri speaks back a summary.
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Meal"
    static let description = IntentDescription(
        "Describe what you ate and MacroLog will parse it, look up the macros, and save the meal.",
        categoryName: "Logging"
    )
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Meal Description",
        requestValueDialog: IntentDialog("What did you eat?")
    )
    var mealDescription: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$mealDescription)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(AppModelContainer.shared)
        do {
            let meal = try await MealLoggingService().logMeal(from: mealDescription, in: context)
            let calories = Int(meal.totalCalories.rounded())
            let needsReview = meal.items.contains { $0.matchConfidence == MatchConfidence.low }
            let itemWord = meal.items.count == 1 ? "item" : "items"
            var summary = "Logged \(meal.items.count) \(itemWord), about \(calories) calories."
            if needsReview {
                summary += " Some items need review in the app."
            }
            return .result(dialog: IntentDialog(stringLiteral: summary))
        } catch let error as MealParsingError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        }
    }
}

/// Registers the Siri phrases. Users can also add this as a custom Shortcut
/// from the Shortcuts app, where the meal text can be piped in as input.
struct MacroLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log meal in \(.applicationName)",
                "Log a meal in \(.applicationName)",
                "Log meal to \(.applicationName)",
                "Log a meal to \(.applicationName)",
                "Log food in \(.applicationName)",
                "Log food to \(.applicationName)",
                "Log my meal in \(.applicationName)",
                "Add a meal to \(.applicationName)",
                "Track a meal in \(.applicationName)",
            ],
            shortTitle: "Log Meal",
            systemImageName: "fork.knife"
        )
    }
}
