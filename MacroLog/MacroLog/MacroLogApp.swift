import SwiftUI
import SwiftData

@main
struct MacroLogApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(AppModelContainer.shared)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var coordinator = MealCaptureCoordinator()
    @ObservedObject private var pendingStore = PendingMealStore.shared
    @State private var showOnboarding = KeychainService.get(.claudeAPIKey) == nil
    @State private var showVoiceLog = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Today", systemImage: "chart.bar.fill") }
            MealListView()
                .tabItem { Label("Meals", systemImage: "fork.knife") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environmentObject(coordinator)
        .fullScreenCover(isPresented: $showVoiceLog) {
            // Presented covers don't reliably inherit environmentObject values
            // from the presenting chain — inject explicitly or VoiceLogView
            // crashes with "No ObservableObject of type MealCaptureCoordinator".
            VoiceLogView()
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .sheet(item: $coordinator.pendingClarification) { pending in
            ClarificationCardView(pending: pending, coordinator: coordinator)
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled()
        }
        .alert("Couldn't log meal", isPresented: .init(
            get: { coordinator.errorMessage != nil },
            set: { if !$0 { coordinator.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coordinator.errorMessage ?? "")
        }
        .onAppear(perform: consumeVoiceCaptureRequest)
        .onChange(of: pendingStore.voiceCaptureRequested) { _, _ in
            consumeVoiceCaptureRequest()
        }
    }

    /// Picks up the Siri intent's open-to-voice request — covers both warm
    /// hand-offs (onChange) and cold launches (onAppear).
    private func consumeVoiceCaptureRequest() {
        guard pendingStore.consumeVoiceCaptureRequest() else { return }
        showVoiceLog = true
    }
}

/// Daily macro targets. These aren't secrets, so plain AppStorage is fine —
/// only API keys live in the Keychain.
enum TargetKeys {
    static let calories = "target_calories"
    static let protein = "target_protein"
    static let carbs = "target_carbs"
    static let fat = "target_fat"
}
