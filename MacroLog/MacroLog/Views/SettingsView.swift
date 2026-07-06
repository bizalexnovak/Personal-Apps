import SwiftUI

struct SettingsView: View {
    @AppStorage(TargetKeys.calories) private var calorieTarget = 2000.0
    @AppStorage(TargetKeys.protein) private var proteinTarget = 150.0
    @AppStorage(TargetKeys.carbs) private var carbTarget = 250.0
    @AppStorage(TargetKeys.fat) private var fatTarget = 70.0

    @State private var claudeKey = ""
    @State private var usdaKey = ""
    @State private var hasSavedClaudeKey = false
    @State private var savedMessageVisible = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily targets") {
                    targetField("Calories (kcal)", value: $calorieTarget)
                    targetField("Protein (g)", value: $proteinTarget)
                    targetField("Carbs (g)", value: $carbTarget)
                    targetField("Fat (g)", value: $fatTarget)
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

    private func targetField(_ label: String, value: Binding<Double>) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
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
