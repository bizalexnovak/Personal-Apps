import SwiftUI

struct SettingsView: View {
    @AppStorage(TargetKeys.calories) private var calorieTarget = 2000.0
    @AppStorage(TargetKeys.protein) private var proteinTarget = 150.0
    @AppStorage(TargetKeys.carbs) private var carbTarget = 250.0
    @AppStorage(TargetKeys.fat) private var fatTarget = 70.0
    @AppStorage(TargetKeys.water) private var waterTarget = 64.0

    // Body metrics. Height stored as total inches; the ft/in fields below are
    // derived from it. Defaults to 0 so recommendations stay hidden until the
    // user actually enters something.
    @AppStorage(BodyKeys.heightInches) private var heightInches = 0.0
    @AppStorage(BodyKeys.weightPounds) private var weightPounds = 0.0
    @AppStorage(BodyKeys.age) private var age = 0.0
    @AppStorage(BodyKeys.sex) private var sexRaw = BiologicalSex.male.rawValue
    @AppStorage(BodyKeys.activity) private var activityRaw = ActivityLevel.moderate.rawValue
    @AppStorage(BodyKeys.goal) private var goalRaw = GoalType.maintain.rawValue

    @State private var claudeKey = ""
    @State private var usdaKey = ""
    @State private var hasSavedClaudeKey = false
    @State private var savedMessageVisible = false
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
        NavigationStack {
            Form {
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
                    Picker("Goal", selection: $goalRaw) {
                        ForEach(GoalType.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } header: {
                    Text("Body & goal")
                } footer: {
                    Text("Used to estimate the calories to reach your goal (Mifflin-St Jeor). Maintain keeps your current weight; Lose trims ~500 kcal/day, Gain adds ~300.")
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
                        Text("Enter your height, weight, and age above to see recommended goals.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recommended daily goals")
                } footer: {
                    Text("A 30% protein / 40% carbs / 30% fat split of your goal calories, and about half your body weight in ounces of water.")
                }

                Section("Daily targets") {
                    targetField("Calories (kcal)", value: $calorieTarget)
                    targetField("Protein (g)", value: $proteinTarget)
                    targetField("Carbs (g)", value: $carbTarget)
                    targetField("Fat (g)", value: $fatTarget)
                    targetField("Water (oz)", value: $waterTarget)
                }

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
                } header: {
                    Text("API keys")
                } footer: {
                    Text("Keys are stored in the iOS Keychain, never in UserDefaults. Without a USDA key the app uses the free public DEMO_KEY, which is rate-limited — get a free key at api.data.gov.")
                }

                Section {
                    NavigationLink("Match diagnostics") {
                        DebugLogView()
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Trace of how each logged item was matched: candidates considered, selection reason, and plausibility flags.")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                hasSavedClaudeKey = KeychainService.get(.claudeAPIKey) != nil
            }
        }
    }

    private func recommendedRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func numberField(_ label: String, value: Binding<Double>, width: CGFloat) -> some View {
        TextField(label, value: value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: width)
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
