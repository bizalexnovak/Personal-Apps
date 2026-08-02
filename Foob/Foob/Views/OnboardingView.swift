import SwiftUI

/// First-launch sheet. Two ways in:
///  - **Invite code** (the path for friends & family): a short code from the
///    developer; AI requests go through the Foob proxy, no Anthropic
///    account needed.
///  - **My own API key** (the developer / power-user path): a Claude key used
///    directly against Anthropic, exactly as before.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Path: String, CaseIterable, Identifiable {
        case invite = "Invite code"
        case ownKey = "My own API key"
        var id: String { rawValue }
    }

    @State private var path: Path = .invite
    @State private var inviteCode = ""
    @State private var claudeKey = ""
    @State private var usdaKey = ""

    private var canStart: Bool {
        switch path {
        case .invite: return !inviteCode.trimmingCharacters(in: .whitespaces).isEmpty
        case .ownKey: return !claudeKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Welcome to Foob")
                            .font(.title2.bold())
                        Text("Describe meals in plain English — by voice, Siri, or typing — and Foob parses them with AI and looks up macros in the USDA food database.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("How will you connect?", selection: $path) {
                        ForEach(Path.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                switch path {
                case .invite:
                    Section {
                        TextField("e.g. MOM-7291", text: $inviteCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Invite code")
                    } footer: {
                        Text("The code you were given by whoever shared Foob with you. That's all you need — AI requests are handled for you.")
                    }
                case .ownKey:
                    Section {
                        SecureField("sk-ant-…", text: $claudeKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Claude API key")
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
                }

                Button("Get started") {
                    save()
                    dismiss()
                }
                .disabled(!canStart)
                .frame(maxWidth: .infinity)
            }
            .keyboardDismissBar()
        }
        .interactiveDismissDisabled(!canStart)
    }

    private func save() {
        switch path {
        case .invite:
            KeychainService.set(
                inviteCode.trimmingCharacters(in: .whitespaces), for: .proxyInviteCode
            )
        case .ownKey:
            KeychainService.set(claudeKey, for: .claudeAPIKey)
            if !usdaKey.isEmpty {
                KeychainService.set(usdaKey, for: .usdaAPIKey)
            }
        }
    }
}
