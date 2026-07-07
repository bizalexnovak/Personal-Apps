import AppIntents
import SwiftData

/// "Log meal in MacroLog" — Siri's only job is capturing the raw text. The
/// intent forwards it to the app and opens it; parsing, clarification cards,
/// and saving all happen in the app UI (no Siri-side dialogs or confirmation).
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Meal"
    static let description = IntentDescription(
        "Describe what you ate and MacroLog will parse it, ask any follow-up questions in the app, and save the meal.",
        categoryName: "Logging"
    )
    static let openAppWhenRun: Bool = true

    @Parameter(
        title: "Meal Description",
        requestValueDialog: IntentDialog("What did you eat?")
    )
    var mealDescription: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$mealDescription)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingMealStore.shared.submit(mealDescription)
        return .result()
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
