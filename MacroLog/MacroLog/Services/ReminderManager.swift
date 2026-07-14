import Foundation
import UserNotifications

/// Legacy single end-of-day reminder settings. Migrated into `ReminderRulesStore`
/// on first load; kept only so the migration can read the old values.
enum ReminderKeys {
    static let enabled = "reminder_enabled"
    static let hour = "reminder_hour"
    static let minute = "reminder_minute"
    static let defaultHour = 20   // 8:00 PM
    static let defaultMinute = 0
}

// MARK: - Rules

/// Which goal a reminder is about. Drives the default message and (for
/// once-a-day reminders) which goal decides whether today's fire is skipped.
enum ReminderMetric: String, Codable, CaseIterable, Identifiable {
    case water, calories, protein, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water: return "Water"
        case .calories: return "Calories"
        case .protein: return "Protein"
        case .general: return "All goals"
        }
    }

    var icon: String {
        switch self {
        case .water: return "drop.fill"
        case .calories: return "flame.fill"
        case .protein: return "fork.knife"
        case .general: return "target"
        }
    }

    /// Default notification text — used for recurring reminders, and as the
    /// fallback for once-a-day ones (whose today-text is the live shortfall).
    var defaultBody: String {
        switch self {
        case .water: return "Water check — log your latest glass and keep going. 💧"
        case .calories: return "Calorie check-in — log anything you've eaten since last time."
        case .protein: return "Protein check — log your latest meal and keep building. 💪"
        case .general: return "Time to check in — log anything you missed and hit your goals. 💪"
        }
    }
}

/// One configured reminder. `daily` fires once at a set time (skipped when the
/// goal is already met that day); `recurring` fires on an interval, but only
/// inside the start–stop window so nights stay quiet.
struct ReminderRule: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case daily, recurring }

    var id = UUID()
    var isEnabled = true
    var metric = ReminderMetric.general
    var kind = Kind.daily

    // Once a day
    var hour = 20
    var minute = 0

    // Recurring
    var intervalMinutes = 120
    var startHour = 8
    var startMinute = 0
    var endHour = 22
    var endMinute = 0

    /// Custom notification text; blank = use the metric's default.
    var customMessage = ""

    var trimmedCustomMessage: String {
        customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var intervalLabel: String {
        if intervalMinutes % 60 == 0 {
            let hours = intervalMinutes / 60
            return hours == 1 ? "hour" : "\(hours) hours"
        }
        return "\(intervalMinutes) min"
    }

    var scheduleSummary: String {
        switch kind {
        case .daily:
            return "Daily at \(Self.timeText(hour, minute))"
        case .recurring:
            return "Every \(intervalLabel), \(Self.timeText(startHour, startMinute))–\(Self.timeText(endHour, endMinute))"
        }
    }

    static func timeText(_ hour: Int, _ minute: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Persistence for the reminder rules (JSON in UserDefaults), with a one-time
/// migration from the original single end-of-day reminder toggle.
enum ReminderRulesStore {
    private static let key = "reminder_rules"

    static func load() -> [ReminderRule] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let rules = try? JSONDecoder().decode([ReminderRule].self, from: data) {
            return rules
        }
        // Migrate the original single end-of-day reminder, if it was on.
        guard defaults.bool(forKey: ReminderKeys.enabled) else { return [] }
        var rule = ReminderRule()
        rule.hour = defaults.object(forKey: ReminderKeys.hour) as? Int ?? ReminderKeys.defaultHour
        rule.minute = defaults.object(forKey: ReminderKeys.minute) as? Int ?? ReminderKeys.defaultMinute
        let rules = [rule]
        save(rules)
        defaults.removeObject(forKey: ReminderKeys.enabled)
        return rules
    }

    static func save(_ rules: [ReminderRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Scheduling

/// Schedules local notifications for every enabled rule. A local notification
/// can't run code when it fires, so once-a-day (goal-aware) reminders are
/// recomputed and rescheduled whenever the day's totals change or the app
/// backgrounds; recurring reminders use repeating calendar triggers so they
/// keep firing even if the app isn't opened.
enum ReminderManager {
    /// All our requests share this prefix so refresh() can clear just ours
    /// (it also matches the legacy "macrolog.end_of_day_reminder" id).
    private static let identifierPrefix = "macrolog."

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Cancel and re-schedule everything based on the current rules + progress.
    static func refresh() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            let rules = ReminderRulesStore.load().filter(\.isEnabled)
            guard !rules.isEmpty else { return }

            let cal = Calendar.current
            var snapshot = WidgetDataStore.read() ?? .empty
            // A snapshot from a previous day means nothing is logged yet today.
            if !cal.isDate(snapshot.date, inSameDayAs: Date()) {
                snapshot = snapshot.clearedForNewDay(date: cal.startOfDay(for: Date()))
            }

            for rule in rules {
                switch rule.kind {
                case .daily: scheduleDaily(rule, snapshot: snapshot, center: center)
                case .recurring: scheduleRecurring(rule, center: center)
                }
            }
        }
    }

    // MARK: Once a day (goal-aware)

    private static func scheduleDaily(
        _ rule: ReminderRule, snapshot: DayNutritionSnapshot, center: UNUserNotificationCenter
    ) {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = rule.hour
        comps.minute = rule.minute
        guard var fireDate = cal.date(from: comps) else { return }

        // Fire today only if the time is still ahead and the goal isn't met;
        // otherwise queue tomorrow's reminder as a fallback.
        let firesToday = fireDate > now && !goalMet(rule.metric, snapshot)
        if !firesToday {
            fireDate = cal.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
        }

        let custom = rule.trimmedCustomMessage
        let content = UNMutableNotificationContent()
        content.title = title(for: rule.metric)
        content.body = custom.isEmpty
            ? (firesToday ? shortfallBody(rule.metric, snapshot) : rule.metric.defaultBody)
            : custom
        content.sound = .default

        let triggerComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        center.add(UNNotificationRequest(
            identifier: "\(identifierPrefix)reminder.\(rule.id.uuidString)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        ))
    }

    // MARK: Recurring (interval within a waking-hours window)

    private static func scheduleRecurring(_ rule: ReminderRule, center: UNUserNotificationCenter) {
        let start = rule.startHour * 60 + rule.startMinute
        let end = rule.endHour * 60 + rule.endMinute
        let interval = max(rule.intervalMinutes, 15)

        // The day's fire times, each as a daily-repeating calendar trigger so
        // they fire even if the app is never opened. Capped so several rules
        // can't blow through iOS's 64 pending-notification limit.
        var slots: [Int] = []
        var minuteOfDay = start
        while minuteOfDay <= max(start, end), slots.count < 20 {
            slots.append(minuteOfDay)
            minuteOfDay += interval
        }

        let custom = rule.trimmedCustomMessage
        for (index, slot) in slots.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = title(for: rule.metric)
            content.body = custom.isEmpty ? rule.metric.defaultBody : custom
            content.sound = .default
            center.add(UNNotificationRequest(
                identifier: "\(identifierPrefix)reminder.\(rule.id.uuidString).\(index)",
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: slot / 60, minute: slot % 60),
                    repeats: true
                )
            ))
        }
    }

    // MARK: Copy & goal checks

    private static func title(for metric: ReminderMetric) -> String {
        metric == .general ? "MacroLog" : "MacroLog — \(metric.title)"
    }

    private static func goalMet(_ metric: ReminderMetric, _ s: DayNutritionSnapshot) -> Bool {
        switch metric {
        case .water: return s.water >= s.waterTarget
        case .calories: return s.calories >= s.calorieTarget
        case .protein: return s.protein >= s.proteinTarget
        case .general:
            return s.calories >= s.calorieTarget
                && s.protein >= s.proteinTarget
                && s.water >= s.waterTarget
        }
    }

    private static func shortfallBody(_ metric: ReminderMetric, _ s: DayNutritionSnapshot) -> String {
        switch metric {
        case .water:
            return "You're still \(Int((s.waterTarget - s.water).rounded())) oz of water short of today's goal. 💧"
        case .calories:
            return "\(Int((s.calorieTarget - s.calories).rounded())) kcal left to hit today's calorie goal."
        case .protein:
            return "\(Int((s.proteinTarget - s.protein).rounded()))g of protein to go today. 💪"
        case .general:
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
            guard !parts.isEmpty else { return metric.defaultBody }
            let list = parts.count == 1
                ? parts[0]
                : parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
            return "You're still \(list) short of today's goals."
        }
    }
}
