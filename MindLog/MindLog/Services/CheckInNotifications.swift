import Foundation
import UserNotifications
import WidgetKit

/// The interactive "how are you feeling?" notification: five mood buttons
/// that write a check-in straight to the shared store without opening the
/// app. Kept separate from ReminderManager's plain daily nudges because this
/// one needs a registered category + action set and a delegate to catch the
/// tap.
enum CheckInNotifications {
    static let categoryIdentifier = "mindlog.checkin"
    private static let actionPrefix = "mindlog.checkin.mood."

    static func actionIdentifier(for mood: Int) -> String { "\(actionPrefix)\(mood)" }

    /// Register the five mood buttons. Call once at launch — UNUserNotification
    /// Center keeps the category around for every check-in request we later
    /// schedule with `categoryIdentifier`.
    static func registerCategories() {
        let actions = Mood.range.map { mood in
            UNNotificationAction(
                identifier: actionIdentifier(for: mood),
                title: "\(Mood.emoji(for: mood)) \(Mood.label(for: mood))",
                options: []
            )
        }
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Pure mapping from a tapped action back to a mood — no notification
    /// center involved, so this is unit-testable on its own.
    static func mood(forActionIdentifier identifier: String) -> Int? {
        guard identifier.hasPrefix(actionPrefix) else { return nil }
        guard let value = Int(identifier.dropFirst(actionPrefix.count)),
              Mood.range.contains(value)
        else { return nil }
        return value
    }
}

/// Handles a tap on one of the mood buttons: writes the check-in into the
/// shared store and asks any home-screen widgets to redraw. Also lets the
/// nudge show as a banner if the app happens to be open when it fires.
final class CheckInNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CheckInNotificationDelegate()

    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let mood = CheckInNotifications.mood(forActionIdentifier: response.actionIdentifier) {
            CheckInWriter.logInSharedStore(mood: mood)
            WidgetCenter.shared.reloadAllTimelines()
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Settings + pure fire-time math for the randomized check-in window. Kept
/// free of UNUserNotificationCenter so the scheduling logic can be unit
/// tested with a seeded generator instead of touching the real notification
/// center.
enum CheckInWindow {
    struct Settings: Codable, Equatable {
        var isEnabled = false
        var startHour = 10
        var endHour = 20
        var perDay = 2
    }

    private static let key = "mindlog_checkin_window"

    static func loadSettings() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    static func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Split the window into `perDay` equal slots and pick one jittered time
    /// per slot, so nudges feel scattered through the day rather than
    /// clockwork — but never close enough together to double up. Randomness
    /// is injected so tests can pass a seeded generator and get a
    /// deterministic result.
    static func fireTimes<G: RandomNumberGenerator>(
        for day: Date,
        settings: Settings,
        calendar: Calendar = .current,
        using generator: inout G
    ) -> [Date] {
        let perDay = min(4, max(1, settings.perDay))
        let startHour = min(settings.startHour, settings.endHour)
        let endHour = max(settings.startHour, settings.endHour)
        guard let dayStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
              let dayEnd = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day),
              dayEnd > dayStart
        else { return [] }

        let totalSeconds = dayEnd.timeIntervalSince(dayStart)
        let slotLength = totalSeconds / Double(perDay)
        // Never jitter into the outer 10% of a slot, so a late pick in one
        // slot and an early pick in the next still keep some breathing room.
        let margin = slotLength * 0.1
        let usable = max(slotLength - margin * 2, 0)

        var times: [Date] = []
        for slot in 0..<perDay {
            let slotStart = dayStart.addingTimeInterval(slotLength * Double(slot))
            let jitter = Double.random(in: 0...usable, using: &generator)
            times.append(slotStart.addingTimeInterval(margin + jitter))
        }
        return times
    }

    /// Convenience overload for real scheduling, where the caller doesn't
    /// care about the generator and just wants system randomness.
    static func fireTimes(
        for day: Date,
        settings: Settings,
        calendar: Calendar = .current
    ) -> [Date] {
        var generator = SystemRandomNumberGenerator()
        return fireTimes(for: day, settings: settings, calendar: calendar, using: &generator)
    }
}
