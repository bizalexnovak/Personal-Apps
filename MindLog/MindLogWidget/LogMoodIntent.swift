import AppIntents
import WidgetKit
import Foundation

/// The five-step mood scale, expressed as an `AppEnum` so it reads well both
/// in the widget's button labels and in Siri/Shortcuts ("Log mood Good in
/// MindLog"). Mirrors `Mood` in the app target, which the widget can't see.
enum MoodChoice: Int, AppEnum {
    case rough = 1
    case low = 2
    case okay = 3
    case good = 4
    case great = 5

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Mood" }
    static var caseDisplayRepresentations: [MoodChoice: DisplayRepresentation] {
        [
            .rough: "😞 Rough",
            .low: "😕 Low",
            .okay: "😐 Okay",
            .good: "🙂 Good",
            .great: "😄 Great",
        ]
    }

    var emoji: String {
        switch self {
        case .rough: return "😞"
        case .low: return "😕"
        case .okay: return "😐"
        case .good: return "🙂"
        case .great: return "😄"
        }
    }

    var label: String {
        switch self {
        case .rough: return "Rough"
        case .low: return "Low"
        case .okay: return "Okay"
        case .good: return "Good"
        case .great: return "Great"
        }
    }
}

/// Logs one mood from the lock screen or home screen — no app launch, no
/// unlock detour. The tap itself is the whole interaction.
///
/// This can't write to the app's SwiftData store directly: the widget runs in
/// its own short-lived process and never opens the app's model container. So
/// it drops a `PendingCheckIn` into the shared App Group queue instead — the
/// app drains that queue into real `JournalEntry` rows next time it launches.
/// The queue entry keeps the tap's own timestamp, so the moment is captured
/// accurately even if the app doesn't open for hours. The snapshot write below
/// is purely cosmetic: it lets the widget redraw with the new mood right away
/// instead of waiting for that eventual drain.
struct LogMoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Mood"
    static let description = IntentDescription(
        "Logs how you're feeling right now, without opening MindLog.",
        categoryName: "Logging"
    )
    /// The whole point of a widget mood button: the tap is the entire
    /// interaction. Opening the app would turn a two-second check-in into a
    /// context switch.
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Mood")
    var mood: MoodChoice

    init() {}

    init(mood: MoodChoice) {
        self.mood = mood
    }

    func perform() async throws -> some IntentResult {
        let now = Date.now
        CheckInInbox.enqueue(
            PendingCheckIn(moodScore: mood.rawValue, timestamp: now, origin: .widget)
        )
        CheckInSnapshotStore.write(
            CheckInSnapshotStore.read().adding(mood: mood.rawValue, at: now)
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
