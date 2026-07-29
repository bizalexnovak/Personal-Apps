import Foundation
import UserNotifications

/// Which habit a reminder nudges. Drives the default message and which part
/// of today's state decides whether today's fire is skipped.
enum ReminderMetric: String, Codable, CaseIterable, Identifiable {
    case checkIn, journal, practice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checkIn: return "Mood check-in"
        case .journal: return "Journal"
        case .practice: return "Practice"
        }
    }

    var icon: String {
        switch self {
        case .checkIn: return "face.smiling"
        case .journal: return "text.book.closed"
        case .practice: return "figure.mind.and.body"
        }
    }

    var defaultBody: String {
        switch self {
        case .checkIn: return "A ten-second check-in: how are you feeling right now?"
        case .journal: return "Take two quiet minutes to get today out of your head and onto the page."
        case .practice: return "A few mindful minutes still count. Breathe, meditate, or step outside."
        }
    }
}

/// One configured daily reminder. Fires at a set time, skipped on days the
/// habit is already done by the time the schedule is refreshed.
struct ReminderRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var isEnabled = true
    var metric = ReminderMetric.checkIn
    var hour = 20
    var minute = 0
    /// Custom notification text; blank = use the metric's default.
    var customMessage = ""

    var trimmedCustomMessage: String {
        customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var scheduleSummary: String {
        "Daily at \(Self.timeText(hour, minute))"
    }

    static func timeText(_ hour: Int, _ minute: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Persistence for the reminder rules (JSON in UserDefaults — times and
/// nudge text, nothing sensitive).
enum ReminderRulesStore {
    private static let key = "mindlog_reminder_rules"

    static func load() -> [ReminderRule] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let rules = try? JSONDecoder().decode([ReminderRule].self, from: data)
        else { return [] }
        return rules
    }

    static func save(_ rules: [ReminderRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// Schedules local notifications for every enabled rule. A local notification
/// can't run code when it fires, so today's fire is decided (done → skipped)
/// whenever the app foregrounds/backgrounds and the schedule is refreshed;
/// the next six days are scheduled unconditionally so reminders keep firing
/// even if the app isn't opened for a while.
enum ReminderManager {
    /// What's already happened today, computed from the model context by the
    /// caller — used to skip today's fire for habits already done.
    struct TodayState {
        var checkedIn = false
        var journaled = false
        var practiced = false

        func isDone(_ metric: ReminderMetric) -> Bool {
            switch metric {
            case .checkIn: return checkedIn
            case .journal: return journaled
            case .practice: return practiced
            }
        }
    }

    /// Today's state computed from the live rows — callers pass their @Query
    /// results so scheduling reflects what's actually been done today.
    static func todayState(
        entries: [JournalEntry], logs: [ActivityLog], calendar: Calendar = .current
    ) -> TodayState {
        let todayEntries = entries.filter { calendar.isDateInToday($0.timestamp) }
        return TodayState(
            checkedIn: todayEntries.contains { $0.moodScore != nil },
            journaled: todayEntries.contains { !$0.isCheckIn },
            practiced: logs.contains { calendar.isDateInToday($0.timestamp) }
        )
    }

    /// All our requests share this prefix so refresh() can clear just ours.
    private static let identifierPrefix = "mindlog."

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Cancel and re-schedule everything based on the current rules + state.
    static func refresh(today: TodayState) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            let rules = ReminderRulesStore.load().filter(\.isEnabled)
            guard !rules.isEmpty else { return }

            let cal = Calendar.current
            let now = Date()
            // Shared budget keeps well under iOS's 64 pending-notification cap.
            var budget = 56
            for rule in rules {
                var comps = cal.dateComponents([.year, .month, .day], from: now)
                comps.hour = rule.hour
                comps.minute = rule.minute
                guard let todayFire = cal.date(from: comps) else { continue }

                let custom = rule.trimmedCustomMessage
                for dayOffset in 0..<7 {
                    guard budget > 0 else { return }
                    guard let fireDate = cal.date(byAdding: .day, value: dayOffset, to: todayFire) else { continue }
                    if dayOffset == 0 {
                        guard fireDate > now, !today.isDone(rule.metric) else { continue }
                    }

                    let content = UNMutableNotificationContent()
                    content.title = "MindLog"
                    content.body = custom.isEmpty ? rule.metric.defaultBody : custom
                    content.sound = .default

                    let triggerComps = cal.dateComponents(
                        [.year, .month, .day, .hour, .minute], from: fireDate
                    )
                    center.add(UNNotificationRequest(
                        identifier: "\(identifierPrefix)reminder.\(rule.id.uuidString).day\(dayOffset)",
                        content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
                    ))
                    budget -= 1
                }
            }
        }
    }
}
