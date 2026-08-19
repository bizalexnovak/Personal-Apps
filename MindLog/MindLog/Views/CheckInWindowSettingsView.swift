import SwiftUI
import SwiftData

/// Turns on (or tunes) the gentle, randomized check-in notifications. Off by
/// default — every edit here persists through `CheckInWindowStore` and
/// re-schedules through `CheckInNotifications.refresh`.
struct CheckInWindowSettingsView: View {
    @Query private var entries: [JournalEntry]
    @Query private var logs: [ActivityLog]

    @State private var window: CheckInWindow = CheckInWindowStore.load()
    @State private var authorizationDenied = false

    var body: some View {
        Form {
            if authorizationDenied {
                Section {
                    Label(
                        "Notifications are off for MindLog. Enable them in Settings to get check-ins.",
                        systemImage: "bell.slash"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle("Gentle check-ins", isOn: Binding(
                    get: { window.isEnabled },
                    set: { newValue in
                        window.isEnabled = newValue
                        if newValue {
                            Task {
                                let granted = await CheckInNotifications.requestAuthorization()
                                authorizationDenied = !granted
                                if !granted { window.isEnabled = false }
                                persist()
                            }
                        } else {
                            persist()
                        }
                    }
                ))
            } footer: {
                Text("A couple of times inside your window below, at an unpredictable moment, MindLog will ask how you're doing — answer straight from the notification, no need to open the app. Off unless you turn it on here.")
            }

            if window.isEnabled {
                Section("Window") {
                    Stepper(
                        "Starts at \(hourText(window.startHour))",
                        value: Binding(
                            get: { window.startHour },
                            set: { window.startHour = $0; persist() }
                        ),
                        in: 0...23
                    )
                    Stepper(
                        "Ends at \(hourText(window.endHour))",
                        value: Binding(
                            get: { window.endHour },
                            set: { window.endHour = $0; persist() }
                        ),
                        in: 1...23
                    )
                    Stepper(
                        "\(window.perDay) a day",
                        value: Binding(
                            get: { window.perDay },
                            set: { window.perDay = $0; persist() }
                        ),
                        in: CheckInWindow.perDayRange
                    )
                } footer: {
                    if window.isValidWindow {
                        Text(window.summary)
                    } else {
                        Text("The end time needs to be after the start time.")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Check-ins")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hourText(_ hour: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func persist() {
        CheckInWindowStore.save(window)
        CheckInNotifications.refresh(
            today: ReminderManager.todayState(entries: entries, logs: logs)
        )
    }
}
