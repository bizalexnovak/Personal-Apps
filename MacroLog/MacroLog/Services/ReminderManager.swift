import Foundation
import UserNotifications

enum ReminderKeys {
    static let enabled = "reminder_enabled"
    static let hour = "reminder_hour"
    static let minute = "reminder_minute"
    static let defaultHour = 20   // 8:00 PM
    static let defaultMinute = 0
}

/// Schedules the optional end-of-day reminder. A local notification can't run
/// code when it fires, so instead we recompute progress and reschedule whenever
/// the day's totals change or the app backgrounds: the reminder is only queued
/// for today when the calorie/protein/water goals aren't yet met (and it's
/// cancelled the moment they are).
enum ReminderManager {
    static let identifier = "macrolog.end_of_day_reminder"

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Cancel and re-schedule based on the current stored snapshot + settings.
    static func refresh() {
        let defaults = UserDefaults.standard
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard defaults.bool(forKey: ReminderKeys.enabled) else { return }

        let hour = defaults.object(forKey: ReminderKeys.hour) as? Int ?? ReminderKeys.defaultHour
        let minute = defaults.object(forKey: ReminderKeys.minute) as? Int ?? ReminderKeys.defaultMinute
        let snapshot = WidgetDataStore.read() ?? .empty

        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        guard var fireDate = cal.date(from: comps) else { return }

        // Fire today only if the time is still ahead and goals aren't met yet;
        // otherwise queue tomorrow's (generic) reminder as a fallback.
        let firesToday = fireDate > now && !goalsMet(snapshot)
        if !firesToday {
            fireDate = cal.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
        }

        let content = UNMutableNotificationContent()
        content.title = "MacroLog"
        content.body = firesToday ? todayBody(snapshot) : genericBody
        content.sound = .default

        let triggerComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    // MARK: - Content

    private static var genericBody: String {
        "Time to wrap up the day — log anything you missed and hit your goals. 💪"
    }

    private static func todayBody(_ s: DayNutritionSnapshot) -> String {
        var parts: [String] = []
        if s.calories < s.calorieTarget {
            parts.append("\(Int((s.calorieTarget - s.calories).rounded())) kcal")
        }
        if s.protein < s.proteinTarget {
            parts.append("\(Int((s.proteinTarget - s.protein).rounded()))g protein")
        }
        if s.water < s.waterTarget {
            parts.append("\(Int((s.waterTarget - s.water).rounded())) oz water")
        }
        guard !parts.isEmpty else { return genericBody }
        let list = parts.count == 1
            ? parts[0]
            : parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
        return "You're still \(list) short of today's goals."
    }

    /// "Met" = calorie, protein, and water targets all reached (carbs/fat are
    /// treated as informational, not hit-or-miss goals).
    private static func goalsMet(_ s: DayNutritionSnapshot) -> Bool {
        s.calories >= s.calorieTarget
            && s.protein >= s.proteinTarget
            && s.water >= s.waterTarget
    }
}
