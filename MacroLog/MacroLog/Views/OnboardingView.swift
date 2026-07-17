import SwiftUI

/// First-launch sheet: collects the Claude API key (required for parsing) and
/// optionally a USDA key. Both go straight to the Keychain.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var claudeKey = ""
    @State private var usdaKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Welcome to MacroLog")
                            .font(.title2.bold())
                        Text("Describe meals in plain English — by Siri or by typing — and MacroLog parses them with Claude and looks up macros in the USDA food database.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    SecureField("sk-ant-…", text: $claudeKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Claude API key (required)")
                } footer: {
                    Text("Create one at console.anthropic.com. Stored in the iOS Keychain.")
                }

                Section {
                    SecureField("Leave empty to use DEMO_KEY", text: $usdaKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("USDA API key (optional)")
                } footer: {
                    Text("The free public DEMO_KEY works out of the box but is rate-limited. Get your own free key at api.data.gov when you're ready.")
                }

                Button("Get started") {
                    KeychainService.set(claudeKey, for: .claudeAPIKey)
                    if !usdaKey.isEmpty {
                        KeychainService.set(usdaKey, for: .usdaAPIKey)
                    }
                    dismiss()
                }
                .disabled(claudeKey.trimmingCharacters(in: .whitespaces).isEmpty)
                .frame(maxWidth: .infinity)
            }
            .keyboardDismissBar()
        }
        .interactiveDismissDisabled(claudeKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}
