import SwiftUI
import SwiftData
import UIKit

/// Settings root: a short menu that drills into focused sub-screens instead of
/// one long scroll. Profile (you + body metrics), Daily goals (targets and the
/// recommended values), API keys, and Developer tools.
struct SettingsView: View {
    @Query private var meals: [Meal]
    @Query private var foods: [CustomFood]

    /// Destination pushed from the root. Routed by case rather than
    /// NavigationLink so rows keep the design's gold chevron instead of the
    /// system disclosure indicator.
    private enum Destination: Hashable {
        case profile, goals, appearance, reminders, foodDatabase, suggestions, apiKeys, developer
    }

    @State private var path: [Destination] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Group {
                    group("YOU", [
                        (.profile, "Profile"),
                        (.goals, "Daily goals"),
                    ])
                    group("APPEARANCE & ALERTS", [
                        (.appearance, "Appearance"),
                        (.reminders, "Reminders"),
                    ])
                    group("DATA", [
                        (.foodDatabase, "Food database"),
                        (.suggestions, "Community suggestions"),
                        (.apiKeys, "API keys"),
                    ])
                    group("DEVELOPER", [
                        (.developer, "Developer"),
                    ])

                    colophon
                        .padding(.top, 30)
                        .padding(.bottom, OrbNavBar.orbOnlyClearance)
                }
                .luxRowChrome()
            }
            .luxList()
            .safeAreaInset(edge: .top, spacing: 0) {
                LuxHeader(title: "SETTINGS", subtitle: "Preferences & your data.")
                    .padding(.bottom, 8)
                    .background(Lux.ground)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .profile: ProfileSettingsView()
                case .goals: GoalsSettingsView()
                case .appearance: AppearanceSettingsView()
                case .reminders: RemindersSettingsView()
                case .foodDatabase: FoodDatabaseView()
                case .suggestions: SuggestionsView()
                case .apiKeys: APIKeysSettingsView()
                case .developer: DeveloperSettingsView()
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ header: String, _ rows: [(Destination, String)]) -> some View {
        LuxSectionHeader(text: header)
            .padding(.top, 22)
            .padding(.bottom, 2)
        ForEach(rows, id: \.0) { destination, title in
            Button { path.append(destination) } label: {
                LuxNavRow(title: title)
            }
            .buttonStyle(.plain)
        }
    }

    /// A quiet line of provenance at the foot of the screen — what the app is
    /// currently holding, rather than a version number nobody reads.
    private var colophon: some View {
        let today = meals.filter { Calendar.current.isDateInToday($0.timestamp) }.count
        return Text("\(today) MEAL\(today == 1 ? "" : "S") TODAY · \(foods.count) FOOD\(foods.count == 1 ? "" : "S") ON FILE")
            .font(Lux.smallcaps(8))
            .tracking(2)
            .foregroundStyle(Lux.cream.opacity(0.4))
            .frame(maxWidth: .infinity)
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Group {
                LuxSectionHeader(text: "NAME")
                    .padding(.top, 18)
                    .padding(.bottom, 2)

                LuxValueRow(label: "FIRST") {
                    TextField("", text: $firstName)
                        .textContentType(.givenName)
                        .font(Lux.serif(19))
                        .foregroundStyle(Lux.cream)
                        .tint(Lux.gold)
                        .multilineTextAlignment(.trailing)
                }
                LuxValueRow(label: "LAST") {
                    TextField("", text: $lastName)
                        .textContentType(.familyName)
                        .font(Lux.serif(19))
                        .foregroundStyle(Lux.cream)
                        .tint(Lux.gold)
                        .multilineTextAlignment(.trailing)
                }

                LuxSectionHeader(text: "BODY")
                    .padding(.top, 26)
                    .padding(.bottom, 2)

                // Height and weight keep their wheel pickers — they're bounded
                // values people scrub to, not type.
                Button { showHeightPicker = true } label: {
                    LuxValueRow(label: "HEIGHT") {
                        Text(heightLabel)
                            .font(Lux.serif(19))
                            .foregroundStyle(Lux.cream)
                    }
                }
                .buttonStyle(.plain)

                Button { showWeightPicker = true } label: {
                    LuxValueRow(label: "WEIGHT") {
                        Text(weightLabel)
                            .font(Lux.serif(19))
                            .foregroundStyle(Lux.cream)
                    }
                }
                .buttonStyle(.plain)

                LuxValueRow(label: "AGE") {
                    HStack(spacing: 5) {
                        TextField("", text: blankableNumber($age))
                            .keyboardType(.numberPad)
                            .font(Lux.serif(19))
                            .monospacedDigit()
                            .foregroundStyle(Lux.cream)
                            .tint(Lux.gold)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 60)
                        Text("YR")
                            .font(Lux.smallcaps(8))
                            .tracking(1.5)
                            .foregroundStyle(Lux.cream.opacity(0.45))
                    }
                }

                LuxValueRow(label: "SEX") {
                    Picker("", selection: $sexRaw) {
                        ForEach(BiologicalSex.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .tint(Lux.gold)
                }

                LuxValueRow(label: "ACTIVITY") {
                    Picker("", selection: $activityRaw) {
                        ForEach(ActivityLevel.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .tint(Lux.gold)
                }

                LuxNote("These feed the recommended daily goals under Daily goals — a Mifflin-St Jeor estimate.")
                    .padding(.top, 14)
                    .padding(.bottom, 40)
            }
            .luxRowChrome()
        }
        .luxList()
        .safeAreaInset(edge: .top, spacing: 0) {
            LuxHeader(title: "PROFILE", subtitle: "You, and the numbers behind your goals.") {
                LuxBackButton { dismiss() }
            } trailing: {
                EmptyView()
            }
            .padding(.bottom, 8)
            .background(Lux.ground)
        }
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissBar()
        .sheet(isPresented: $showHeightPicker) { heightPicker }
        .sheet(isPresented: $showWeightPicker) { weightPicker }
        .onAppear(perform: migrateLegacyName)
    }

    // MARK: Height / weight wheel pickers

    private var heightLabel: String {
        guard heightInches > 0 else { return "—" }
        return "\(Int(feet.wrappedValue)) ft \(min(Int(inchesRemainder.rounded()), 11)) in"
    }

    private var weightLabel: String {
        weightPounds > 0 ? "\(Int(weightPounds.rounded())) lb" : "—"
    }

    // The wheel bindings clamp into the pickers' ranges so an unset value (0)
    // or legacy fractional inches never leave the wheel without a valid
    // selection; nothing is written back until the user actually scrolls.
    //
    // These were inline DisclosureGroups; as sheets the ruled rows stay a
    // uniform height instead of one of them growing a 130pt wheel mid-list.
    private var heightPicker: some View {
        let feetInt = Binding(
            get: { min(max(Int(feet.wrappedValue), 1), 8) },
            set: { feet.wrappedValue = Double($0) }
        )
        let inchesInt = Binding(
            get: { min(max(Int(inchesRemainder.rounded()), 0), 11) },
            set: { inches.wrappedValue = Double($0) }
        )
        return wheelSheet(title: "HEIGHT") {
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
        }
    }

    private var weightPicker: some View {
        let weightInt = Binding(
            get: { min(max(Int(weightPounds.rounded()), 50), 600) },
            set: { weightPounds = Double($0) }
        )
        return wheelSheet(title: "WEIGHT") {
            Picker("Weight", selection: weightInt) {
                ForEach(50...600, id: \.self) { Text("\($0) lb").tag($0) }
            }
            .pickerStyle(.wheel)
        }
    }

    private func wheelSheet<Wheel: View>(title: String, @ViewBuilder wheel: () -> Wheel) -> some View {
        LuxSheet {
            VStack(spacing: 0) {
                Text(title)
                    .font(Lux.title(20))
                    .tracking(3)
                    .engravedFill()
                    .padding(.top, 20)
                wheel()
                    .frame(height: 150)
                    .tint(Lux.cream)
                    .padding(.top, 10)
                Spacer()
            }
            .padding(.horizontal, Lux.hPad)
        }
        .presentationDetents([.height(280)])
    }

    /// One-time split of the old single "name" field into first/last.
    private func migrateLegacyName() {
        guard firstName.isEmpty, lastName.isEmpty, !legacyName.isEmpty else { return }
        let parts = legacyName.split(separator: " ").map(String.init)
        firstName = parts.first ?? ""
        lastName = parts.dropFirst().joined(separator: " ")
    }

}


// MARK: - Daily goals

/// The goal type + recommended values derived from Profile, and the manual
/// daily targets that drive the Today rings and Trends chart.
struct GoalsSettingsView: View {
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Group {
                LuxSwitcher(
                    options: GoalType.allCases.map { ($0.rawValue, $0.title.uppercased()) },
                    selection: $goalRaw,
                    spacing: 22,
                    size: 10
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

                LuxNote("Maintain keeps your current weight; Lose trims ~500 kcal a day, Gain adds ~300.")
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                LuxSectionHeader(text: "RECOMMENDED FOR YOU")
                    .padding(.top, 26)
                    .padding(.bottom, 2)

                if let rec = recommended {
                    recommendedRow("CALORIES", "\(Int(rec.calories)) kcal")
                    recommendedRow("PROTEIN", "\(Int(rec.protein)) g")
                    recommendedRow("CARBS", "\(Int(rec.carbs)) g")
                    recommendedRow("FAT", "\(Int(rec.fat)) g")
                    recommendedRow("WATER", "\(Int(rec.waterOunces)) oz")

                    Button("APPLY TO MY TARGETS") { applyRecommended(rec) }
                        .buttonStyle(GhostCapsule(gold: true))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)

                    if appliedMessageVisible {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                            Text("TARGETS UPDATED")
                                .font(Lux.smallcaps(8))
                                .tracking(2)
                        }
                        .foregroundStyle(Lux.gold)
                        .padding(.top, 10)
                    }

                    LuxNote("A 30 / 40 / 30 split of your goal calories across protein, carbs and fat, and about half your body weight in ounces of water.")
                        .padding(.top, 12)
                } else {
                    LuxNote("Add your height, weight, and age under Profile to see recommended goals.", size: 15)
                        .padding(.top, 6)
                }

                LuxSectionHeader(text: "DAILY TARGETS")
                    .padding(.top, 26)
                    .padding(.bottom, 2)

                targetField("CALORIES", value: $calorieTarget)
                targetField("PROTEIN (G)", value: $proteinTarget)
                targetField("CARBS (G)", value: $carbTarget)
                targetField("FAT (G)", value: $fatTarget)
                targetField("WATER (OZ)", value: $waterTarget)

                LuxNote("These are what the Today rings and the Trends chart measure against.")
                    .padding(.top, 14)
                    .padding(.bottom, 40)
            }
            .luxRowChrome()
        }
        .luxList()
        .safeAreaInset(edge: .top, spacing: 0) {
            LuxHeader(title: "DAILY GOALS", subtitle: "What a good day looks like.") {
                LuxBackButton { dismiss() }
            } trailing: {
                EmptyView()
            }
            .padding(.bottom, 8)
            .background(Lux.ground)
        }
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissBar()
    }

    private func recommendedRow(_ label: String, _ value: String) -> some View {
        LuxValueRow(label: label) {
            Text(value)
                .font(Lux.serif(19))
                .monospacedDigit()
                .foregroundStyle(Lux.cream.opacity(0.75))
        }
    }

    private func targetField(_ label: String, value: Binding<Double>) -> some View {
        LuxValueRow(label: label) {
            TextField("", text: blankableNumber(value))
                .keyboardType(.decimalPad)
                .font(Lux.serif(21))
                .monospacedDigit()
                .foregroundStyle(Lux.gold)
                .tint(Lux.gold)
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

/// Theme preference and the custom background colour. The metric colours are
/// no longer adjustable — see the note in the body.
struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ThemeKeys.appearance) private var appearanceRaw = AppearanceMode.dark.rawValue
    @AppStorage(ThemeKeys.background) private var colorBackground = ""

    var body: some View {
        List {
            Group {
                LuxSectionHeader(text: "THEME")
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                HStack(spacing: 10) {
                    ForEach(AppearanceMode.allCases) { mode in
                        themeSwatch(mode)
                    }
                }

                LuxNote("Light and Dark are fixed. Auto follows the time of day. Custom uses your background colour below.")
                    .padding(.top, 12)

                LuxSectionHeader(text: "METALWORK")
                    .padding(.top, 26)
                    .padding(.bottom, 2)

                HStack(spacing: 12) {
                    Text("Gold & emerald")
                        .font(Lux.serif(18))
                        .foregroundStyle(Lux.cream)
                    Spacer()
                    Circle().fill(Lux.goldFill).frame(width: 16, height: 16)
                    Circle().fill(Lux.panel)
                        .overlay(Circle().stroke(Lux.controlBorder, lineWidth: 1))
                        .frame(width: 16, height: 16)
                }
                .luxRow()

                // The app accent and the five per-metric pickers were retired
                // with this design: the gold ladder is load-bearing now. Trends
                // leans on it for series identity and the Today rings for their
                // own tracks, so a user-chosen hue would break the chart rather
                // than personalise it. Any colours previously stored are simply
                // ignored — nothing to migrate.
                LuxNote("Metric colours follow the gold ladder and are no longer adjustable — the Trends chart uses them to tell its five lines apart.")
                    .padding(.top, 12)

                LuxSectionHeader(text: "CUSTOM BACKGROUND")
                    .padding(.top, 26)
                    .padding(.bottom, 2)

                LuxValueRow(label: "BACKGROUND") {
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { Color(hex: colorBackground) ?? Lux.ground },
                            set: { colorBackground = $0.hexString }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }

                if !colorBackground.isEmpty {
                    Button("RESET BACKGROUND") { colorBackground = "" }
                        .buttonStyle(GhostCapsule())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                }

                LuxNote("Used when Theme is set to Custom. Text switches to light or dark based on how dark this colour is.")
                    .padding(.top, 12)
                    .padding(.bottom, 40)
            }
            .luxRowChrome()
        }
        .luxList()
        .safeAreaInset(edge: .top, spacing: 0) {
            LuxHeader(title: "APPEARANCE", subtitle: "How Foob looks.") {
                LuxBackButton { dismiss() }
            } trailing: {
                EmptyView()
            }
            .padding(.bottom, 8)
            .background(Lux.ground)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .dark }

    /// Each theme as a swatch card showing what it actually looks like, rather
    /// than a word in a segmented control.
    private func themeSwatch(_ mode: AppearanceMode) -> some View {
        let selected = appearance == mode
        return Button {
            appearanceRaw = mode.rawValue
        } label: {
            VStack(spacing: 8) {
                swatchFill(mode)
                    .frame(height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: Lux.panelRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Lux.panelRadius)
                            .stroke(selected ? Lux.gold : Lux.controlBorder,
                                    lineWidth: selected ? 1.5 : 1))
                Text(mode.title.uppercased())
                    .font(Lux.smallcaps(8))
                    .tracking(2)
                    .foregroundStyle(selected ? Lux.cream : Lux.cream.opacity(0.45))
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: Lux.panelRadius)
                    .fill(selected ? Lux.gold.opacity(0.06) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func swatchFill(_ mode: AppearanceMode) -> some View {
        switch mode {
        case .light:
            Color(hex: "#f2ead9")!
        case .dark:
            Lux.ground
        case .auto:
            // Split down the middle: parchment by day, emerald by night.
            HStack(spacing: 0) {
                Color(hex: "#f2ead9")!
                Lux.ground
            }
        case .custom:
            AngularGradient(
                colors: [Lux.goldBright, Lux.gold, Lux.bronze, Lux.panel, Lux.goldBright],
                center: .center)
        }
    }
}

// MARK: - Reminders

/// Goal reminders: any number of once-a-day (goal-aware) or recurring
/// (interval within a waking-hours window) notifications, each with an
/// optional custom message. Scheduling lives in ReminderManager.
struct RemindersSettingsView: View {
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Group {
                if rules.isEmpty {
                    LuxNote("No reminders yet — add one below.", size: 15)
                        .padding(.top, 24)
                }
                ForEach($rules) { $rule in
                    ruleRow($rule)
                }
                .onDelete { rules.remove(atOffsets: $0) }

                Button("ADD REMINDER") { editorTarget = .new }
                    .buttonStyle(GhostCapsule(gold: true))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 18)

                LuxNote("Once-a-day reminders are skipped when that goal is already met. Recurring ones repeat on their interval, but only between their start and stop times — so nights stay quiet.")
                    .padding(.top, 14)
                    .padding(.bottom, 40)
            }
            .luxRowChrome()
        }
        .luxList()
        .safeAreaInset(edge: .top, spacing: 0) {
            LuxHeader(title: "REMINDERS", subtitle: "Nudges, on your terms.") {
                LuxBackButton { dismiss() }
            } trailing: {
                EmptyView()
            }
            .padding(.bottom, 8)
            .background(Lux.ground)
        }
        .toolbar(.hidden, for: .navigationBar)
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
            Group {
                switch target {
                case .new:
                    ReminderEditorView(rule: ReminderRule(), title: "New Reminder") { upsert($0) }
                case .edit(let rule):
                    ReminderEditorView(rule: rule, title: "Edit Reminder") { upsert($0) }
                }
            }
            .luxSheetChrome()
        }
        .alert("Notifications are off", isPresented: $showDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Turn on notifications for Foob in Settings to get reminders.")
        }
    }

    /// Metric + schedule (tap to edit) with an enable toggle on the right.
    private func ruleRow(_ rule: Binding<ReminderRule>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.wrappedValue.metric.title.uppercased())
                    .font(Lux.smallcaps(9))
                    .tracking(2)
                    .foregroundStyle(Lux.goldLabel)
                Text(rule.wrappedValue.scheduleSummary)
                    .font(Lux.serif(18))
                    .foregroundStyle(Lux.cream)
                if !rule.wrappedValue.trimmedCustomMessage.isEmpty {
                    Text("\u{201C}\(rule.wrappedValue.trimmedCustomMessage)\u{201D}")
                        .font(Lux.serifItalic(14))
                        .foregroundStyle(Lux.cream.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editorTarget = .edit(rule.wrappedValue) }

            LuxToggle(isOn: Binding(
                get: { rule.wrappedValue.isEnabled },
                set: { isOn in
                    rule.wrappedValue.isEnabled = isOn
                    if isOn { ensureAuthorized() }
                }
            ))
            .accessibilityLabel("Enabled")
        }
        .luxRow(vertical: 12)
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
    @State private var inviteCode = ""
    @State private var proxyURL = UserDefaults.standard.string(forKey: ClaudeEndpoint.proxyURLDefaultsKey) ?? ""
    @State private var claudeKey = ""
    @State private var usdaKey = ""
    @State private var spoonacularKey = ""
    @State private var edamamAppID = ""
    @State private var edamamAppKey = ""
    @State private var hasSavedInviteCode = false
    @State private var hasSavedClaudeKey = false
    @State private var hasSavedSpoonacular = false
    @State private var hasSavedEdamam = false
    @State private var savedMessageVisible = false

    private var hasInput: Bool {
        ![inviteCode, claudeKey, usdaKey, spoonacularKey, edamamAppID, edamamAppKey]
            .allSatisfy { $0.isEmpty }
            || proxyURL != (UserDefaults.standard.string(forKey: ClaudeEndpoint.proxyURLDefaultsKey) ?? "")
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Group {
                LuxSectionHeader(text: "INVITE CODE")
                    .padding(.top, 18)
                    .padding(.bottom, 2)

                keyRow("CODE", text: $inviteCode, saved: hasSavedInviteCode,
                       secure: false, capitalization: .characters)
                keyRow("PROXY URL", text: $proxyURL, saved: false, secure: false)

                LuxNote("Friends & family: just the code you were given. The proxy URL only matters if the app wasn't built with one baked in. An invite code takes priority over a personal Claude key below.")
                    .padding(.top, 12)

                LuxSectionHeader(text: "PERSONAL KEYS")
                    .padding(.top, 26)
                    .padding(.bottom, 2)

                keyRow("CLAUDE", text: $claudeKey, saved: hasSavedClaudeKey)
                keyRow("USDA", text: $usdaKey, saved: false)

                LuxNote("Keys live in the iOS Keychain, never in UserDefaults. Without a USDA key the app uses the free public DEMO_KEY, which is rate-limited — get your own at api.data.gov.")
                    .padding(.top, 12)

                LuxSectionHeader(text: "RECIPE SEARCH")
                    .padding(.top, 26)
                    .padding(.bottom, 2)

                keyRow("SPOONACULAR", text: $spoonacularKey, saved: hasSavedSpoonacular)
                keyRow("EDAMAM APP ID", text: $edamamAppID, saved: hasSavedEdamam)
                keyRow("EDAMAM APP KEY", text: $edamamAppKey, saved: hasSavedEdamam)

                LuxNote("TheMealDB works with no key. Spoonacular and Edamam each offer a free tier with far more recipes, and nutrition included.")
                    .padding(.top, 12)

                Button("SAVE KEYS") { saveKeys() }
                    .buttonStyle(GoldCapsule(enabled: hasInput))
                    .disabled(!hasInput)
                    .padding(.top, 24)

                if savedMessageVisible {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                        Text("SAVED TO KEYCHAIN")
                            .font(Lux.smallcaps(8))
                            .tracking(2)
                    }
                    .foregroundStyle(Lux.gold)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }

                Color.clear.frame(height: 40)
            }
            .luxRowChrome()
        }
        .luxList()
        .safeAreaInset(edge: .top, spacing: 0) {
            LuxHeader(title: "API KEYS", subtitle: "How Foob reaches the outside world.") {
                LuxBackButton { dismiss() }
            } trailing: {
                EmptyView()
            }
            .padding(.bottom, 8)
            .background(Lux.ground)
        }
        .toolbar(.hidden, for: .navigationBar)
        .keyboardDismissBar()
        .onAppear {
            hasSavedInviteCode = KeychainService.get(.proxyInviteCode) != nil
            hasSavedClaudeKey = KeychainService.get(.claudeAPIKey) != nil
            hasSavedSpoonacular = KeychainService.get(.spoonacularAPIKey) != nil
            hasSavedEdamam = KeychainService.get(.edamamAppID) != nil
                && KeychainService.get(.edamamAppKey) != nil
        }
    }

    /// One key row. A gold SAVED tag stands in for the old "(saved)"
    /// placeholder text, so the field can stay empty and still say that
    /// something is stored without ever showing it.
    private func keyRow(
        _ label: String, text: Binding<String>, saved: Bool,
        secure: Bool = true, capitalization: TextInputAutocapitalization = .never
    ) -> some View {
        HStack(spacing: 10) {
            LuxFieldLabel(text: label)
            Spacer()
            if saved, text.wrappedValue.isEmpty {
                Text("SAVED")
                    .font(Lux.smallcaps(7))
                    .tracking(1.5)
                    .foregroundStyle(Lux.gold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().stroke(Lux.controlBorder, lineWidth: 1))
            }
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .font(Lux.serifItalic(16))
            .foregroundStyle(Lux.cream)
            .tint(Lux.gold)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled()
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 150)
        }
        .luxRow(vertical: 10)
    }

    private func saveKeys() {
        if !inviteCode.isEmpty {
            KeychainService.set(
                inviteCode.trimmingCharacters(in: .whitespaces), for: .proxyInviteCode
            )
            inviteCode = ""
            hasSavedInviteCode = true
        }
        // The URL override is saved as typed, including clearing it.
        UserDefaults.standard.set(
            proxyURL.trimmingCharacters(in: .whitespaces),
            forKey: ClaudeEndpoint.proxyURLDefaultsKey
        )
        if !claudeKey.isEmpty {
            KeychainService.set(claudeKey, for: .claudeAPIKey)
            claudeKey = ""
            hasSavedClaudeKey = true
        }
        if !usdaKey.isEmpty {
            KeychainService.set(usdaKey, for: .usdaAPIKey)
            usdaKey = ""
        }
        if !spoonacularKey.isEmpty {
            KeychainService.set(spoonacularKey, for: .spoonacularAPIKey)
            spoonacularKey = ""
            hasSavedSpoonacular = true
        }
        if !edamamAppID.isEmpty {
            KeychainService.set(edamamAppID, for: .edamamAppID)
            edamamAppID = ""
        }
        if !edamamAppKey.isEmpty {
            KeychainService.set(edamamAppKey, for: .edamamAppKey)
            edamamAppKey = ""
        }
        hasSavedEdamam = KeychainService.get(.edamamAppID) != nil
            && KeychainService.get(.edamamAppKey) != nil
        savedMessageVisible = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            savedMessageVisible = false
        }
    }
}

// MARK: - Developer

struct DeveloperSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showDiagnostics = false

    var body: some View {
        List {
            Group {
                Button { showDiagnostics = true } label: {
                    LuxNavRow(title: "Match diagnostics")
                }
                .buttonStyle(.plain)
                .padding(.top, 18)

                LuxNote("Trace of how each logged item was matched: candidates considered, selection reason, and plausibility flags.")
                    .padding(.top, 12)
            }
            .luxRowChrome()
        }
        .luxList()
        .safeAreaInset(edge: .top, spacing: 0) {
            LuxHeader(title: "DEVELOPER", subtitle: "Under the hood.") {
                LuxBackButton { dismiss() }
            } trailing: {
                EmptyView()
            }
            .padding(.bottom, 8)
            .background(Lux.ground)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showDiagnostics) {
            DebugLogView()
        }
    }
}
