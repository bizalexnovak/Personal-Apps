import AppIntents

/// "Log meal in Foob" — Siri's only job is opening the app onto the voice
/// capture screen. Speech recording, transcription, clarification, and saving
/// all happen in the app (see CaptureView + MealCaptureCoordinator).
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Meal"
    static let description = IntentDescription(
        "Opens Foob listening for your meal description.",
        categoryName: "Logging"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureHub.shared.goVoice()
        return .result()
    }
}

/// "Log drink in Foob" — same voice capture as Log Meal; the parser handles
/// water and other beverages. A separate command so saying "log drink" feels
/// natural when you're drinking rather than eating.
struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Drink"
    static let description = IntentDescription(
        "Opens Foob listening for what you drank.",
        categoryName: "Logging"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureHub.shared.goVoice()
        return .result()
    }
}

/// "Scan a label in Foob" — opens the app straight to the camera to
/// photograph a nutrition facts label.
struct ScanLabelIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Label"
    static let description = IntentDescription(
        "Opens Foob's camera to scan a nutrition label.",
        categoryName: "Logging"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureHub.shared.goScan()
        return .result()
    }
}

/// Registers the Siri phrases. Also available as building blocks in the
/// Shortcuts app.
struct FoobShortcuts: AppShortcutsProvider {
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
        AppShortcut(
            intent: LogDrinkIntent(),
            phrases: [
                "Log drink in \(.applicationName)",
                "Log a drink in \(.applicationName)",
                "Log drink to \(.applicationName)",
                "Log a drink to \(.applicationName)",
                "Log water in \(.applicationName)",
                "Log a beverage in \(.applicationName)",
                "Track a drink in \(.applicationName)",
            ],
            shortTitle: "Log Drink",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: ScanLabelIntent(),
            phrases: [
                "Scan a label in \(.applicationName)",
                "Scan label in \(.applicationName)",
                "Scan an item in \(.applicationName)",
                "Scan food in \(.applicationName)",
                "Scan a nutrition label in \(.applicationName)",
            ],
            shortTitle: "Scan Label",
            systemImageName: "camera.viewfinder"
        )
    }
}
