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
    @StateObject private var coordinator = MealCaptureCoordinator()
    @ObservedObject private var pendingStore = PendingMealStore.shared
    @State private var showOnboarding = KeychainService.get(.claudeAPIKey) == nil

    @AppStorage(ThemeKeys.appearance) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(ThemeKeys.colorCalories) private var colorCalories = ""
    @AppStorage(ThemeKeys.colorProtein) private var colorProtein = ""
    @AppStorage(ThemeKeys.colorCarbs) private var colorCarbs = ""
    @AppStorage(ThemeKeys.colorFat) private var colorFat = ""
    @AppStorage(ThemeKeys.colorWater) private var colorWater = ""

    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    private var palette: MetricPalette {
        MetricPalette.resolved(
            calories: colorCalories, protein: colorProtein, carbs: colorCarbs,
            fat: colorFat, water: colorWater
        )
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Today", systemImage: "chart.bar.fill") }
            MealListView()
                .tabItem { Label("Log", systemImage: "plus.circle.fill") }
            HistoryView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(palette.calories)
        .environment(\.metricPalette, palette)
        .preferredColorScheme(appearance.colorScheme)
        .environmentObject(coordinator)
        // The capture screen handles voice/scan/text AND renders the review
        // inline — there's no separate review cover anymore.
        .fullScreenCover(item: $pendingStore.request) { request in
            CaptureView(mode: request.mode)
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .alert("Couldn't log meal", isPresented: .init(
            get: { coordinator.errorMessage != nil },
            set: { if !$0 { coordinator.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coordinator.errorMessage ?? "")
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
    static let water = "target_water"
}

/// Personal profile fields (non-secret) shown under Settings → Profile.
enum ProfileKeys {
    static let name = "profile_name"
}

/// Body metrics used to derive recommended daily goals (Mifflin-St Jeor).
/// Not secrets — plain AppStorage. Height is stored as total inches so the
/// ft/in fields in Settings compute against a single source of truth.
enum BodyKeys {
    static let heightInches = "body_height_inches"
    static let weightPounds = "body_weight_pounds"
    static let age = "body_age"
    static let sex = "body_sex"          // BiologicalSex.rawValue
    static let activity = "body_activity" // ActivityLevel.rawValue
    static let goal = "body_goal"         // GoalType.rawValue
}
