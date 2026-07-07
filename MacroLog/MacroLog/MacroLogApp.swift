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
        .onAppear(perform: consumePendingSiriText)
        .onChange(of: pendingStore.pendingText) { _, _ in
            consumePendingSiriText()
        }
    }

    /// Picks up a transcript forwarded by LogMealIntent — covers both warm
    /// hand-offs (onChange) and cold launches (onAppear).
    private func consumePendingSiriText() {
        guard let text = pendingStore.consume() else { return }
        Task { await coordinator.begin(text: text, in: modelContext) }
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
