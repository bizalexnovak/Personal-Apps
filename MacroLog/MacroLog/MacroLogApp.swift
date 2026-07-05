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
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
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
