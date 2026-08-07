import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.appBackground) private var appBackground
    @AppStorage(ProfileKeys.firstName) private var firstName = ""
    @AppStorage(GoalKeys.scoreGoal) private var scoreGoal = PracticeScore.defaultGoal

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Daily practice goal")
                            Spacer()
                            Text("\(Int(scoreGoal)) points")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $scoreGoal, in: 10...100, step: 5)
                    }
                } header: {
                    Text("Daily goal")
                } footer: {
                    Text("Your practice score adds up what you do for your mind each day — activities earn points per minute (with daily caps, so variety beats grinding), journaling adds \(Int(PracticeScore.journalBonus)), a mood check-in adds \(Int(PracticeScore.checkInBonus)). The default goal of \(Int(PracticeScore.defaultGoal)) ≈ one real practice plus a journal entry.")
                }

                Section("Nudges") {
                    NavigationLink {
                        RemindersSettingsView()
                    } label: {
                        Label("Reminders", systemImage: "bell")
                    }
                    NavigationLink {
                        CheckInWindowSettingsView()
                    } label: {
                        Label("Check-ins", systemImage: "bell.badge")
                    }
                }

                // A soft ask, never a gate: the card hides itself on devices
                // without Health, and the app is complete without it.
                Section("Health") {
                    HealthAccessCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Appearance") {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Theme & colours", systemImage: "paintbrush")
                    }
                }

                Section {
                    Label {
                        Text("Everything — journal entries, moods, activities — is stored only on this iPhone. Nothing is uploaded, and speech recognition runs on-device whenever your language supports it.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("MindLog is a self-reflection tool, not a medical device. If you're struggling, reach out to someone — in the US, call or text 988 for the Suicide & Crisis Lifeline.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .keyboardDismissBar()
            .appBackground(appBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Reminders

/// Manage the daily nudges. Rules persist via ReminderRulesStore; every edit
/// re-schedules through ReminderManager with today's live state.
struct RemindersSettingsView: View {
    @Query private var entries: [JournalEntry]
    @Query private var logs: [ActivityLog]

    @State private var rules: [ReminderRule] = ReminderRulesStore.load()
    @State private var editingIndex: Int?
    @State private var authorizationDenied = false

    var body: some View {
        Form {
            if authorizationDenied {
                Section {
                    Label(
                        "Notifications are off for MindLog. Enable them in Settings to get reminders.",
                        systemImage: "bell.slash"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }
            Section {
                // The tappable row and the enable toggle are siblings, not
                // nested — a Toggle inside a Button's label can lose its taps
                // to the button in a Form.
                ForEach(rules.indices, id: \.self) { index in
                    HStack {
                        Button {
                            editingIndex = index
                        } label: {
                            HStack {
                                Image(systemName: rules[index].metric.icon)
                                    .foregroundStyle(rules[index].isEnabled ? Color.accentColor : .secondary)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rules[index].metric.title)
                                        .foregroundStyle(.primary)
                                    Text(rules[index].scheduleSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Toggle("", isOn: Binding(
                            get: { rules[index].isEnabled },
                            set: { rules[index].isEnabled = $0; persist() }
                        ))
                        .labelsHidden()
                    }
                }
                .onDelete { offsets in
                    rules.remove(atOffsets: offsets)
                    persist()
                }

                Button {
                    Task {
                        let granted = await ReminderManager.requestAuthorization()
                        authorizationDenied = !granted
                        guard granted else { return }
                        rules.append(ReminderRule())
                        persist()
                        editingIndex = rules.count - 1
                    }
                } label: {
                    Label("Add reminder", systemImage: "plus")
                }
            } footer: {
                Text("Daily nudges that skip themselves once the habit is done for the day — a check-in reminder stays quiet on days you've already checked in.")
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { editingIndex != nil },
            set: { if !$0 { editingIndex = nil } }
        ), onDismiss: {
            // Edits stream into `rules` live, so a swipe-down dismissal must
            // persist and reschedule too — not just the Done button. persist()
            // is idempotent, so the Done path saving twice is harmless.
            persist()
        }) {
            if let index = editingIndex, rules.indices.contains(index) {
                ReminderEditSheet(rule: Binding(
                    get: { rules[index] },
                    set: { rules[index] = $0 }
                ), onDone: {
                    persist()
                    editingIndex = nil
                })
            }
        }
    }

    private func persist() {
        ReminderRulesStore.save(rules)
        ReminderManager.refresh(today: ReminderManager.todayState(entries: entries, logs: logs))
    }
}

private struct ReminderEditSheet: View {
    @Binding var rule: ReminderRule
    var onDone: () -> Void

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(hour: rule.hour, minute: rule.minute)
                ) ?? .now
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                rule.hour = comps.hour ?? 20
                rule.minute = comps.minute ?? 0
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Remind me to") {
                    Picker("Habit", selection: $rule.metric) {
                        ForEach(ReminderMetric.allCases) { metric in
                            Label(metric.title, systemImage: metric.icon).tag(metric)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("At") {
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                Section {
                    TextField("Custom message", text: $rule.customMessage, axis: .vertical)
                } header: {
                    Text("Message")
                } footer: {
                    Text("Leave blank for: “\(rule.metric.defaultBody)”")
                }
            }
            .keyboardDismissBar()
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @AppStorage(ThemeKeys.appearance) private var appearanceRaw = AppearanceMode.dark.rawValue
    @AppStorage(ThemeKeys.appAccent) private var accentHex = ""
    @AppStorage(ThemeKeys.background) private var backgroundHex = ""
    @AppStorage(ThemeKeys.colorMood) private var moodHex = ""
    @AppStorage(ThemeKeys.colorScore) private var scoreHex = ""
    @AppStorage(ThemeKeys.colorMinutes) private var minutesHex = ""

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .dark
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Auto follows the time of day (dark from 7 pm to 7 am). Custom uses your background colour below.")
            }

            Section("App colours") {
                colorRow("Accent", hex: $accentHex, defaultColor: MetricPalette.defaultAppAccent)
                if appearance == .custom {
                    colorRow("Background", hex: $backgroundHex, defaultColor: Color(.systemBackground))
                }
            }

            Section {
                colorRow("Mood", hex: $moodHex, defaultColor: Metric.mood.color)
                colorRow("Practice score", hex: $scoreHex, defaultColor: Metric.score.color)
                colorRow("Activity minutes", hex: $minutesHex, defaultColor: Metric.minutes.color)
            } header: {
                Text("Chart colours")
            } footer: {
                Text("Used by the Today ring and the Trends charts.")
            }

            Section {
                Button("Reset to defaults") {
                    accentHex = ""
                    backgroundHex = ""
                    moodHex = ""
                    scoreHex = ""
                    minutesHex = ""
                }
            }
        }
        .navigationTitle("Theme & colours")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func colorRow(_ title: String, hex: Binding<String>, defaultColor: Color) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(hex: hex.wrappedValue) ?? defaultColor },
            set: { hex.wrappedValue = $0.hexString }
        ), supportsOpacity: false)
    }
}
