import Foundation
import UserNotifications
import WidgetKit

/// A gentle, randomized window of interactive check-in notifications — the
/// kind you answer with a tap on the mood you're feeling, right from the lock
/// screen, without ever opening the app. Nothing about this nudges toward a
/// streak; it just offers a quiet moment to notice how you are.
struct CheckInWindow: Codable, Equatable {
    /// Off unless someone explicitly turns it on — a check-in that can pop up
    /// unbidden is a bigger ask than a single daily reminder at a time you
    /// picked, so this one doesn't get to default itself on.
    var isEnabled = false
    var startHour = 10
    var endHour = 21
    /// How many check-ins land inside the window each day.
    var perDay = 2

    /// Clamps `perDay` into the supported range; callers editing via a
    /// Stepper should still route through this so a bad value never persists.
    static let perDayRange = 1...4

    var isValidWindow: Bool { endHour > startHour }

    var summary: String {
        guard isValidWindow else { return "Set a valid window" }
        let start = Self.hourText(startHour)
        let end = Self.hourText(endHour)
        return "\(perDay) a day, \(start) – \(end)"
    }

    private static func hourText(_ hour: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Persistence for the check-in window (JSON in UserDefaults — just a couple
/// of hours and a count, nothing sensitive), mirroring `ReminderRulesStore`.
enum CheckInWindowStore {
    private static let key = "mindlog_checkin_window"

    static func load() -> CheckInWindow {
        guard let data = UserDefaults.standard.data(forKey: key),
              let window = try? JSONDecoder().decode(CheckInWindow.self, from: data)
        else { return CheckInWindow() }
        return window
    }

    static func save(_ window: CheckInWindow) {
        guard let data = try? JSONEncoder().encode(window) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// Schedules the interactive check-in notifications and hands their taps back
/// to the app via the App Group inbox.
enum CheckInNotifications {
    static let categoryIdentifier = "mindlog.checkin"

    /// `ReminderManager.refresh` clears every pending request whose
    /// identifier starts with "mindlog." before it re-schedules its own —
    /// that prefix would sweep ours away too if we shared it. Using a
    /// distinct prefix lets the two schedulers run independently, each only
    /// ever touching its own requests.
    static let identifierPrefix = "checkin."

    /// One action per mood, 1 (roughest) through 5 (best) — matches the scale
    /// used everywhere else moods are logged.
    private static func actionIdentifier(forMood mood: Int) -> String {
        "checkin.mood.\(mood)"
    }

    private static let moodActionTitles: [Int: String] = [
        1: "😞 Rough",
        2: "🙁 Low",
        3: "😐 Okay",
        4: "🙂 Good",
        5: "😄 Great",
    ]

    /// A few warm, plain openers — rotated by day so the notification never
    /// feels like a canned prompt.
    private static let bodies = [
        "A quiet moment — how are you, right now?",
        "No rush. How's the mind doing right now?",
        "A ten-second pause — where are you at?",
        "Just checking in. How does right now feel?",
    ]

    /// Registers the interactive category. `options: []` on every action —
    /// deliberately not `.foreground` — is the whole point: answering a
    /// check-in should never have to open the app.
    static func registerCategories() {
        let actions = (1...5).map { mood in
            UNNotificationAction(
                identifier: actionIdentifier(forMood: mood),
                title: moodActionTitles[mood] ?? "\(mood)",
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

    // MARK: - Scheduling math

    /// Pure, deterministic-given-a-seed scheduling: for each of `daysAhead`
    /// days, split [startHour, endHour) into `perDay` equal sub-windows and
    /// pick one random minute inside each, so check-ins feel unpredictable
    /// but never cluster together or land in the middle of the night. Kept
    /// free of UNUserNotificationCenter so it's unit-testable without a
    /// device.
    static func fireTimes(
        window: CheckInWindow,
        daysAhead: Int,
        from now: Date,
        calendar: Calendar = .current,
        using generator: inout some RandomNumberGenerator
    ) -> [Date] {
        guard window.isEnabled, window.isValidWindow, daysAhead > 0 else { return [] }

        let totalMinutes = (window.endHour - window.startHour) * 60
        let slotMinutes = totalMinutes / window.perDay
        guard slotMinutes > 0 else { return [] }

        var results: [Date] = []
        for dayOffset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let startOfDay = calendar.startOfDay(for: day)

            for slot in 0..<window.perDay {
                let slotStartMinute = window.startHour * 60 + slot * slotMinutes
                // Last slot absorbs any remainder from integer division so the
                // window is fully covered instead of leaving a dead gap at the end.
                let slotEndMinute = slot == window.perDay - 1
                    ? window.endHour * 60
                    : slotStartMinute + slotMinutes
                let span = max(slotEndMinute - slotStartMinute, 1)
                let offsetMinute = Int.random(in: 0..<span, using: &generator)
                let minuteOfDay = slotStartMinute + offsetMinute

                guard let fireDate = calendar.date(
                    byAdding: .minute, value: minuteOfDay, to: startOfDay
                ) else { continue }

                if fireDate > now {
                    results.append(fireDate)
                }
            }
        }
        return results.sorted()
    }

    // MARK: - Live scheduling

    static func requestAuthorization() async -> Bool {
        await ReminderManager.requestAuthorization()
    }

    /// Cancel and re-schedule just our own pending requests. Skips today's
    /// fires once the user has already checked in today — later days always
    /// schedule, since there's no way yet to know they'll be done.
    static func refresh(today: ReminderManager.TodayState) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            let window = CheckInWindowStore.load()
            guard window.isEnabled else { return }

            let calendar = Calendar.current
            let now = Date()
            var generator = SystemRandomNumberGenerator()
            // 3 days ahead × up to 4/day = at most 12 candidates; the budget
            // below caps what actually gets scheduled. Kept small (max 8) so
            // this stays well under iOS's shared 64-pending cap alongside
            // ReminderManager's own budget of 56.
            let times = fireTimes(
                window: window, daysAhead: 3, from: now, calendar: calendar, using: &generator
            )

            var budget = 8
            for (index, fireDate) in times.enumerated() {
                guard budget > 0 else { break }
                if calendar.isDateInToday(fireDate), today.checkedIn { continue }

                let content = UNMutableNotificationContent()
                content.title = "MindLog"
                content.body = bodies[index % bodies.count]
                content.categoryIdentifier = categoryIdentifier
                content.sound = .default

                let triggerComps = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: fireDate
                )
                center.add(UNNotificationRequest(
                    identifier: "\(identifierPrefix)\(fireDate.timeIntervalSince1970)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
                ))
                budget -= 1
            }
        }
    }
}

/// Handles taps on the check-in notification's mood actions.
final class CheckInNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CheckInNotificationDelegate()

    private override init() { super.init() }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard let mood = (1...5).first(where: {
            response.actionIdentifier == "checkin.mood.\($0)"
        }) else { return }

        // This callback runs briefly in the background with no app process
        // guaranteed to be alive — writing straight to SwiftData here isn't
        // safe. Enqueuing into the App Group inbox lets the app drain it via
        // `CheckInSync.drain` the next time it foregrounds, while keeping the
        // tap's own timestamp rather than whenever the app happened to open.
        let checkIn = PendingCheckIn(moodScore: mood, timestamp: .now, origin: .notification)
        CheckInInbox.enqueue(checkIn)
        CheckInSnapshotStore.write(CheckInSnapshotStore.read().adding(mood: mood, at: checkIn.timestamp))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Lets a check-in still show (and be answered) while the app is open in
    /// the foreground, instead of being silently swallowed.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
