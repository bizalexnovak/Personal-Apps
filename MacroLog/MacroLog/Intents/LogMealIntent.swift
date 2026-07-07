import AppIntents

/// "Log meal in MacroLog" — Siri's only job is opening the app onto the voice
/// capture screen. Speech recording, transcription, clarification, and saving
/// all happen in the app (see VoiceLogView + MealCaptureCoordinator).
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Meal"
    static let description = IntentDescription(
        "Opens MacroLog listening for your meal description.",
        categoryName: "Logging"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingMealStore.shared.requestVoiceCapture()
        return .result()
    }
}

/// Registers the Siri phrases. Also available as a building block in the
/// Shortcuts app.
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
