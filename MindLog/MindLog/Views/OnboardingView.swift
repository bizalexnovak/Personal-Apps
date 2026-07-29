import SwiftUI

/// First-launch sheet: what the app is, the privacy promise, a name for the
/// greeting, and an optional evening check-in reminder. No accounts, no keys.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent
    @AppStorage(ProfileKeys.firstName) private var firstName = ""
    @AppStorage(OnboardingKeys.completed) private var completed = false

    @State private var wantsReminder = true
    @State private var reminderTime =
        Calendar.current.date(from: DateComponents(hour: 20, minute: 30)) ?? .now

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "figure.mind.and.body")
                            .font(.system(size: 40))
                            .foregroundStyle(accent)
                        Text("A quiet place for your head")
                            .font(.title2.weight(.bold))
                        Text("Speak or type what's on your mind, check in on your mood, and give yourself credit for the things that help — meditating, walking, calling a friend.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        bullet("lock.shield", "Private by design",
                               "Everything stays on this iPhone. No account, no cloud, no analytics.")
                        bullet("mic.fill", "Voice-first journaling",
                               "Tap the mic and talk. Pauses are fine — it waits for you.")
                        bullet("chart.xyaxis.line", "See what actually helps",
                               "Trends connect your practices to your mood over time.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What should we call you?")
                            .font(.headline)
                        TextField("First name (optional)", text: $firstName)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.givenName)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $wantsReminder) {
                            Text("Evening check-in reminder")
                                .font(.headline)
                        }
                        if wantsReminder {
                            DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            Text("One gentle nudge a day, and it skips itself once you've checked in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        finish()
                    } label: {
                        Text("Start")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(24)
            }
            .keyboardDismissBar()
            .interactiveDismissDisabled()
        }
    }

    private func bullet(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func finish() {
        if wantsReminder {
            Task {
                let granted = await ReminderManager.requestAuthorization()
                if granted {
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                    var rule = ReminderRule()
                    rule.metric = .checkIn
                    rule.hour = comps.hour ?? 20
                    rule.minute = comps.minute ?? 30
                    ReminderRulesStore.save([rule])
                    ReminderManager.refresh(today: ReminderManager.TodayState())
                }
                completed = true
                dismiss()
            }
        } else {
            completed = true
            dismiss()
        }
    }
}

enum OnboardingKeys {
    static let completed = "onboarding_completed"
}
