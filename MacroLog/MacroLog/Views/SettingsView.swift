import SwiftUI
import UIKit

/// Settings root: a short menu that drills into focused sub-screens instead of
/// one long scroll. Profile (you + body metrics), Daily goals (targets and the
/// recommended values), API keys, and Developer tools.
struct SettingsView: View {
    @Environment(\.appBackground) private var appBackground

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ProfileSettingsView()
                } label: {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                NavigationLink {
                    GoalsSettingsView()
                } label: {
                    Label("Daily goals", systemImage: "target")
                }
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("Appearance", systemImage: "paintpalette")
                }
                NavigationLink {
                    RemindersSettingsView()
                } label: {
                    Label("Reminders", systemImage: "bell")
                }
                NavigationLink {
                    APIKeysSettingsView()
                } label: {
                    Label("API keys", systemImage: "key.fill")
                }
                NavigationLink {
                    DeveloperSettingsView()
                } label: {
                    Label("Developer", systemImage: "wrench.and.screwdriver")
                }
            }
            .appBackground(appBackground)
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Numeric input helper

/// A String binding over a Double that shows blank for 0 (so a leading "0"
/// never gets appended to what you type) and parses back on edit.
func blankableNumber(_ value: Binding<Double>) -> Binding<String> {
    Binding(
        get: {
            let v = value.wrappedValue
            if v == 0 { return "" }
            return v == v.rounded() ? String(Int(v)) : String(v)
        },
        set: { value.wrappedValue = Double($0.filter { $0.isNumber || $0 == "." }) ?? 0 }
    )
}

// MARK: - Profile

/// Your name and the body metrics that feed the recommended-goal formula.
struct ProfileSettingsView: View {
    @Environment(\.appBackground) private var appBackground
    @AppStorage(ProfileKeys.firstName) private var firstName = ""
    @AppStorage(ProfileKeys.lastName) private var lastName = ""
    @AppStorage(ProfileKeys.name) private var legacyName = ""

    @AppStorage(BodyKeys.heightInches) private var heightInches = 0.0
    @AppStorage(BodyKeys.weightPounds) private var weightPounds = 0.0
    @AppStorage(BodyKeys.age) private var age = 0.0
    @AppStorage(BodyKeys.sex) private var sexRaw = BiologicalSex.male.rawValue
    @AppStorage(BodyKeys.activity) private var activityRaw = ActivityLevel.moderate.rawValue

    @State private var showHeightPicker = false
    @State private var showWeightPicker = false

    // Height split into feet + inches, both writing back to heightInches.
    private var feet: Binding<Double> {
        Binding(
            get: { (heightInches / 12).rounded(.down) },
            set: { heightInches = $0 * 12 + inchesRemainder }
        )
    }
    private var inches: Binding<Double> {
        Binding(
            get: { inchesRemainder },
            set: { heightInches = feet.wrappedValue * 12 + $0 }
        )
    }
    private var inchesRemainder: Double { heightInches - (heightInches / 12).rounded(.down) * 12 }

    var body: some View {
        Form {
            Section("You") {
                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                TextField("Last name", text: $lastName)
                    .textContentType(.familyName)
            }

            Section {
                heightRow
                weightRow
                LabeledContent("Age") {
                    HStack(spacing: 4) {
                        numberField("yr", value: $age, width: 72)
                        Text("yr").foregroundStyle(.secondary)
                    }
                }
                Picker("Sex", selection: $sexRaw) {
                    ForEach(BiologicalSex.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Activity", selection: $activityRaw) {
                    ForEach(ActivityLevel.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("Body")
            } footer: {
                Text("These feed the recommended daily goals under Settings → Daily goals (Mifflin-St Jeor estimate).")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissBar()
        .appBackground(appBackground)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: migrateLegacyName)
    }

    // MARK: Height / weight wheel pickers

    private var heightLabel: String {
        guard heightInches > 0 else { return "—" }
        return "\(Int(feet.wrappedValue)) ft \(min(Int(inchesRemainder.rounded()), 11)) in"
    }

    // The wheel bindings clamp into the pickers' ranges so an unset value (0)
    // or legacy fractional inches never leave the wheel without a valid
    // selection; nothing is written back until the user actually scrolls.
    private var heightRow: some View {
        let feetInt = Binding(
            get: { min(max(Int(feet.wrappedValue), 1), 8) },
            set: { feet.wrappedValue = Double($0) }
        )
        let inchesInt = Binding(
            get: { min(max(Int(inchesRemainder.rounded()), 0), 11) },
            set: { inches.wrappedValue = Double($0) }
        )
        return DisclosureGroup(isExpanded: $showHeightPicker) {
            HStack(spacing: 0) {
                Picker("Feet", selection: feetInt) {
                    ForEach(1...8, id: \.self) { Text("\($0) ft").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                Picker("Inches", selection: inchesInt) {
                    ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 130)
        } label: {
            LabeledContent("Height", value: heightLabel)
        }
    }

    private var weightRow: some View {
        let weightInt = Binding(
            get: { min(max(Int(weightPounds.rounded()), 50), 600) },
            set: { weightPounds = Double($0) }
        )
        return DisclosureGroup(isExpanded: $showWeightPicker) {
            Picker("Weight", selection: weightInt) {
                ForEach(50...600, id: \.self) { Text("\($0) lb").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(height: 130)
        } label: {
            LabeledContent("Weight", value: weightPounds > 0 ? "\(Int(weightPounds.rounded())) lb" : "—")
        }
    }

    /// One-time split of the old single "name" field into first/last.
    private func migrateLegacyName() {
        guard firstName.isEmpty, lastName.isEmpty, !legacyName.isEmpty else { return }
        let parts = legacyName.split(separator: " ").map(String.init)
        firstName = parts.first ?? ""
        lastName = parts.dropFirst().joined(separator: " ")
    }

    private func numberField(_ label: String, value: Binding<Double>, width: CGFloat) -> some View {
        TextField(label, text: blankableNumber(value))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: width)
    }
}

// MARK: - Daily goals

/// The goal type + recommended values derived from Profile, and the manual
/// daily targets that drive the Today rings and Trends chart.
struct GoalsSettingsView: View {
    @Environment(\.appBackground) private var appBackground
    @AppStorage(TargetKeys.calories) private var calorieTarget = 2000.0
    @AppStorage(TargetKeys.protein) private var proteinTarget = 150.0
    @AppStorage(TargetKeys.carbs) private var carbTarget = 250.0
    @AppStorage(TargetKeys.fat) private var fatTarget = 70.0
    @AppStorage(TargetKeys.water) private var waterTarget = 64.0

    @AppStorage(BodyKeys.heightInches) private var heightInches = 0.0
    @AppStorage(BodyKeys.weightPounds) private var weightPounds = 0.0
    @AppStorage(BodyKeys.age) private var age = 0.0
    @AppStorage(BodyKeys.sex) private var sexRaw = BiologicalSex.male.rawValue
    @AppStorage(BodyKeys.activity) private var activityRaw = ActivityLevel.moderate.rawValue
    @AppStorage(BodyKeys.goal) private var goalRaw = GoalType.maintain.rawValue

    @State private var appliedMessageVisible = false

    private var sex: BiologicalSex { BiologicalSex(rawValue: sexRaw) ?? .male }
    private var activity: ActivityLevel { ActivityLevel(rawValue: activityRaw) ?? .moderate }
    private var goal: GoalType { GoalType(rawValue: goalRaw) ?? .maintain }

    private var recommended: RecommendedGoals? {
        GoalCalculator.recommended(
            sex: sex, heightInches: heightInches, weightPounds: weightPounds,
            ageYears: age, activity: activity, goal: goal
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Goal", selection: $goalRaw) {
                    ForEach(GoalType.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("Goal")
            } footer: {
                Text("Maintain keeps your current weight; Lose trims ~500 kcal/day, Gain adds ~300.")
            }

            Section {
                if let rec = recommended {
                    recommendedRow("Calories", "\(Int(rec.calories)) kcal")
                    recommendedRow("Protein", "\(Int(rec.protein)) g")
                    recommendedRow("Carbs", "\(Int(rec.carbs)) g")
                    recommendedRow("Fat", "\(Int(rec.fat)) g")
                    recommendedRow("Water", "\(Int(rec.waterOunces)) oz")

                    Button("Apply to my targets") {
                        applyRecommended(rec)
                    }

                    if appliedMessageVisible {
                        Label("Targets updated", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    }
                } else {
                    Text("Add your height, weight, and age under Settings → Profile to see recommended goals.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Recommended")
            } footer: {
                Text("A 30% protein / 40% carbs / 30% fat split of your goal calories, and about half your body weight in ounces of water.")
            }

            Section {
                targetField("Calories (kcal)", value: $calorieTarget)
                targetField("Protein (g)", value: $proteinTarget)
                targetField("Carbs (g)", value: $carbTarget)
                targetField("Fat (g)", value: $fatTarget)
                targetField("Water (oz)", value: $waterTarget)
            } header: {
                Text("Daily targets")
            } footer: {
                Text("These are what the Today rings and Trends chart measure against. Apply the recommended values above, or set them by hand.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissBar()
        .appBackground(appBackground)
        .navigationTitle("Daily goals")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recommendedRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func targetField(_ label: String, value: Binding<Double>) -> some View {
        LabeledContent(label) {
            TextField(label, text: blankableNumber(value))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }

    private func applyRecommended(_ rec: RecommendedGoals) {
        calorieTarget = rec.calories
        proteinTarget = rec.protein
        carbTarget = rec.carbs
        fatTarget = rec.fat
        waterTarget = rec.waterOunces
        appliedMessageVisible = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            appliedMessageVisible = false
        }
    }
}

// MARK: - Appearance

/// Light/dark preference and the customizable metric colors used by the Today
/// rings/bar and the Trends chart.
struct AppearanceSettingsView: View {
    @Environment(\.appBackground) private var appBackground
    @AppStorage(ThemeKeys.appearance) private var appearanceRaw = AppearanceMode.dark.rawValue
    @AppStorage(ThemeKeys.appAccent) private var colorAppAccent = ""
    @AppStorage(ThemeKeys.background) private var colorBackground = ""
    @AppStorage(ThemeKeys.colorCalories) private var colorCalories = ""
    @AppStorage(ThemeKeys.colorProtein) private var colorProtein = ""
    @AppStorage(ThemeKeys.colorCarbs) private var colorCarbs = ""
    @AppStorage(ThemeKeys.colorFat) private var colorFat = ""
    @AppStorage(ThemeKeys.colorWater) private var colorWater = ""

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Theme")
            } footer: {
                Text("Light and Dark are fixed. Auto follows the time of day. Custom uses your background colour below.")
            }

            Section {
                colorRow("App color", store: $colorAppAccent, default: MetricPalette.defaultAppAccent)
                Button("Reset app color", role: .destructive) { colorAppAccent = "" }
            } header: {
                Text("App color")
            } footer: {
                Text("Tints buttons, the active tab, and the capture controls.")
            }

            Section {
                colorRow("Background", store: $colorBackground, default: defaultBackgroundSwatch)
                if !colorBackground.isEmpty {
                    Button("Reset background", role: .destructive) { colorBackground = "" }
                }
                if appearance != .custom {
                    Button("Switch to Custom theme") { appearanceRaw = AppearanceMode.custom.rawValue }
                        .font(.subheadline)
                }
            } header: {
                Text("Custom background")
            } footer: {
                Text("Used when Theme is set to Custom. Text automatically switches to light or dark based on how dark this colour is.")
            }

            Section {
                colorRow("Calories", store: $colorCalories, default: MetricPalette.default.calories)
                colorRow("Protein", store: $colorProtein, default: MetricPalette.default.protein)
                colorRow("Carbs", store: $colorCarbs, default: MetricPalette.default.carbs)
                colorRow("Fat", store: $colorFat, default: MetricPalette.default.fat)
                colorRow("Water", store: $colorWater, default: MetricPalette.default.water)

                Button("Reset to defaults", role: .destructive) {
                    colorCalories = ""; colorProtein = ""; colorCarbs = ""
                    colorFat = ""; colorWater = ""
                }
            } header: {
                Text("Colors")
            } footer: {
                Text("Used for the Today rings and bar and the Trends chart lines.")
            }
        }
        .appBackground(appBackground)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var defaultBackgroundSwatch: Color { Color(uiColor: .systemBackground) }

    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .dark }

    private func colorRow(_ label: String, store: Binding<String>, default def: Color) -> some View {
        ColorPicker(
            label,
            selection: Binding(
                get: { Color(hex: store.wrappedValue) ?? def },
                set: { store.wrappedValue = $0.hexString }
            ),
            supportsOpacity: false
        )
    }
}

// MARK: - Reminders

/// Goal reminders: any number of once-a-day (goal-aware) or recurring
/// (interval within a waking-hours window) notifications, each with an
/// optional custom message. Scheduling lives in ReminderManager.
struct RemindersSettingsView: View {
    @Environment(\.appBackground) private var appBackground
    @State private var rules: [ReminderRule] = []
    @State private var editorTarget: EditorTarget?
    @State private var showDenied = false
    /// What's currently on disk — persist only when `rules` actually diverges,
    /// so opening the screen never rewrites or re-prompts for anything.
    @State private var savedRules: [ReminderRule] = []

    private enum EditorTarget: Identifiable {
        case new
        case edit(ReminderRule)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let rule): return rule.id.uuidString
            }
        }
    }

    var body: some View {
        List {
            Section {
                if rules.isEmpty {
                    Text("No reminders yet — add one below.")
                        .foregroundStyle(.secondary)
                }
                ForEach($rules) { $rule in
                    ruleRow($rule)
                }
                .onDelete { rules.remove(atOffsets: $0) }
            } footer: {
                Text("Once-a-day reminders are skipped when that goal is already met. Recurring ones repeat on their interval, but only between their start and stop times — so nights stay quiet.")
            }

            Section {
                Button {
                    editorTarget = .new
                } label: {
                    Label("Add reminder", systemImage: "plus")
                }
            }
        }
        .appBackground(appBackground)
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard savedRules.isEmpty, rules.isEmpty else { return }
            rules = ReminderRulesStore.load()
            savedRules = rules
        }
        .onChange(of: rules) { _, _ in
            guard rules != savedRules else { return }
            savedRules = rules
            ReminderRulesStore.save(rules)
            ReminderManager.refresh()
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                ReminderEditorView(rule: ReminderRule(), title: "New Reminder") { upsert($0) }
            case .edit(let rule):
                ReminderEditorView(rule: rule, title: "Edit Reminder") { upsert($0) }
            }
        }
        .alert("Notifications are off", isPresented: $showDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Turn on notifications for MacroLog in Settings to get reminders.")
        }
    }

    /// Name + schedule (tap to edit) with an enable toggle on the right.
    private func ruleRow(_ rule: Binding<ReminderRule>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label(rule.wrappedValue.metric.title, systemImage: rule.wrappedValue.metric.icon)
                Text(rule.wrappedValue.scheduleSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !rule.wrappedValue.trimmedCustomMessage.isEmpty {
                    Text("\u{201C}\(rule.wrappedValue.trimmedCustomMessage)\u{201D}")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editorTarget = .edit(rule.wrappedValue) }
            Toggle("Enabled", isOn: Binding(
                get: { rule.wrappedValue.isEnabled },
                set: { isOn in
                    rule.wrappedValue.isEnabled = isOn
                    if isOn { ensureAuthorized() }
                }
            ))
            .labelsHidden()
        }
    }

    private func upsert(_ rule: ReminderRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        if rule.isEnabled { ensureAuthorized() }
    }

    /// Ask for notification permission — only ever off the back of an explicit
    /// user action (enabling or saving a reminder), never from just looking.
    private func ensureAuthorized() {
        Task {
            let granted = await ReminderManager.requestAuthorization()
            if !granted {
                await MainActor.run { showDenied = true }
            }
        }
    }
}

/// Create/edit one reminder: goal, once-a-day vs recurring schedule, and an
/// optional custom message (blank = the default shown as the placeholder).
private struct ReminderEditorView: View {
    @State var rule: ReminderRule
    let title: String
    var onSave: (ReminderRule) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let intervals: [(minutes: Int, label: String)] = [
        (30, "30 minutes"), (60, "Hour"), (90, "90 minutes"),
        (120, "2 hours"), (180, "3 hours"), (240, "4 hours"), (360, "6 hours"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Remind me about") {
                    Picker("Goal", selection: $rule.metric) {
                        ForEach(ReminderMetric.allCases) { metric in
                            Label(metric.title, systemImage: metric.icon).tag(metric)
                        }
                    }
                }

                Section {
                    Picker("Repeats", selection: $rule.kind) {
                        Text("Once a day").tag(ReminderRule.Kind.daily)
                        Text("Recurring").tag(ReminderRule.Kind.recurring)
                    }
                    .pickerStyle(.segmented)

                    if rule.kind == .daily {
                        DatePicker(
                            "Time",
                            selection: time($rule.hour, $rule.minute),
                            displayedComponents: .hourAndMinute
                        )
                    } else {
                        Picker("Every", selection: $rule.intervalMinutes) {
                            ForEach(Self.intervals, id: \.minutes) { interval in
                                Text(interval.label).tag(interval.minutes)
                            }
                        }
                        DatePicker(
                            "Start",
                            selection: time($rule.startHour, $rule.startMinute),
                            displayedComponents: .hourAndMinute
                        )
                        DatePicker(
                            "Stop",
                            selection: time($rule.endHour, $rule.endMinute),
                            displayedComponents: .hourAndMinute
                        )
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text(rule.kind == .daily
                        ? "Fires at this time — unless that goal is already met for the day."
                        : "Repeats on this interval every day, only between Start and Stop — set them around your sleep. A Stop before the Start wraps past midnight (e.g. 10 PM–6 AM).")
                }

                Section {
                    TextField(rule.metric.defaultBody, text: $rule.customMessage, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Message")
                } footer: {
                    Text("Leave blank to use the default shown above. Once-a-day reminders using the default show your live shortfall (e.g. \u{201C}still 24 oz of water short\u{201D}).")
                }
            }
            .keyboardDismissBar()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(rule)
                        dismiss()
                    }
                }
            }
        }
    }

    /// Maps an hour/minute pair to a Date for DatePicker and back on edit.
    private func time(_ hour: Binding<Int>, _ minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(hour: hour.wrappedValue, minute: minute.wrappedValue)
                ) ?? .now
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                hour.wrappedValue = comps.hour ?? 0
                minute.wrappedValue = comps.minute ?? 0
            }
        )
    }
}

// MARK: - API keys

struct APIKeysSettingsView: View {
    @Environment(\.appBackground) private var appBackground
    @State private var claudeKey = ""
    @State private var usdaKey = ""
    @State private var hasSavedClaudeKey = false
    @State private var savedMessageVisible = false

    var body: some View {
        Form {
            Section {
                SecureField(
                    hasSavedClaudeKey ? "Claude API key (saved)" : "Claude API key",
                    text: $claudeKey
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                SecureField("USDA API key (optional)", text: $usdaKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Save keys") {
                    saveKeys()
                }
                .disabled(claudeKey.isEmpty && usdaKey.isEmpty)

                if savedMessageVisible {
                    Label("Saved to Keychain", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
            } footer: {
                Text("Keys are stored in the iOS Keychain, never in UserDefaults. Without a USDA key the app uses the free public DEMO_KEY, which is rate-limited — get a free key at api.data.gov.")
            }
        }
        .appBackground(appBackground)
        .keyboardDismissBar()
        .navigationTitle("API keys")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasSavedClaudeKey = KeychainService.get(.claudeAPIKey) != nil
        }
    }

    private func saveKeys() {
        if !claudeKey.isEmpty {
            KeychainService.set(claudeKey, for: .claudeAPIKey)
            claudeKey = ""
            hasSavedClaudeKey = true
        }
        if !usdaKey.isEmpty {
            KeychainService.set(usdaKey, for: .usdaAPIKey)
            usdaKey = ""
        }
        savedMessageVisible = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            savedMessageVisible = false
        }
    }
}

// MARK: - Developer

struct DeveloperSettingsView: View {
    @Environment(\.appBackground) private var appBackground

    var body: some View {
        Form {
            Section {
                NavigationLink("Match diagnostics") {
                    DebugLogView()
                }
            } footer: {
                Text("Trace of how each logged item was matched: candidates considered, selection reason, and plausibility flags.")
            }
        }
        .appBackground(appBackground)
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
    }
}
