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

// MARK: - Profile

/// Your name and the body metrics that feed the recommended-goal formula.
struct ProfileSettingsView: View {
    @Environment(\.appBackground) private var appBackground
    @AppStorage(ProfileKeys.name) private var name = ""

    @AppStorage(BodyKeys.heightInches) private var heightInches = 0.0
    @AppStorage(BodyKeys.weightPounds) private var weightPounds = 0.0
    @AppStorage(BodyKeys.age) private var age = 0.0
    @AppStorage(BodyKeys.sex) private var sexRaw = BiologicalSex.male.rawValue
    @AppStorage(BodyKeys.activity) private var activityRaw = ActivityLevel.moderate.rawValue

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
                TextField("Name", text: $name)
                    .textContentType(.givenName)
            }

            Section {
                HStack {
                    Text("Height")
                    Spacer()
                    numberField("ft", value: feet, width: 52)
                    Text("ft").foregroundStyle(.secondary)
                    numberField("in", value: inches, width: 52)
                    Text("in").foregroundStyle(.secondary)
                }
                LabeledContent("Weight") {
                    HStack(spacing: 4) {
                        numberField("lb", value: $weightPounds, width: 72)
                        Text("lb").foregroundStyle(.secondary)
                    }
                }
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
        .appBackground(appBackground)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func numberField(_ label: String, value: Binding<Double>, width: CGFloat) -> some View {
        TextField(label, value: value, format: .number)
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
            TextField(label, value: value, format: .number)
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
    @AppStorage(ThemeKeys.appearance) private var appearanceRaw = AppearanceMode.system.rawValue
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
                Text("System follows your device's light/dark setting.")
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
                if colorBackground.isEmpty {
                    ColorPicker(
                        "Background",
                        selection: Binding(
                            get: { Color(hex: colorBackground) ?? defaultBackgroundSwatch },
                            set: { colorBackground = $0.hexString }
                        ),
                        supportsOpacity: false
                    )
                    Text("Currently following the \(appearanceLabel) background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    colorRow("Background", store: $colorBackground, default: defaultBackgroundSwatch)
                    Button("Use system background", role: .destructive) { colorBackground = "" }
                }
            } header: {
                Text("Background")
            } footer: {
                Text("Overrides the light/dark background across the app. Pick a shade that keeps text readable, or reset to follow the system.")
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

    private var appearanceLabel: String {
        (AppearanceMode(rawValue: appearanceRaw) ?? .system).title.lowercased()
    }

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
