import SwiftUI
import SwiftData
import Combine

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
    @StateObject private var hub = CaptureHub()
    @ObservedObject private var pendingStore = PendingMealStore.shared
    @State private var showOnboarding = KeychainService.get(.claudeAPIKey) == nil
    /// Ticks so Auto re-evaluates day/night across the 7am / 7pm boundaries.
    @State private var now = Date()

    @AppStorage(ThemeKeys.appearance) private var appearanceRaw = AppearanceMode.dark.rawValue
    @AppStorage(ThemeKeys.appAccent) private var colorAppAccent = ""
    @AppStorage(ThemeKeys.background) private var colorBackground = ""
    @AppStorage(ThemeKeys.colorCalories) private var colorCalories = ""
    @AppStorage(ThemeKeys.colorProtein) private var colorProtein = ""
    @AppStorage(ThemeKeys.colorCarbs) private var colorCarbs = ""
    @AppStorage(ThemeKeys.colorFat) private var colorFat = ""
    @AppStorage(ThemeKeys.colorWater) private var colorWater = ""

    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .dark }
    private var appAccent: Color { Color(hex: colorAppAccent) ?? MetricPalette.defaultAppAccent }

    /// The custom background only applies in Custom mode; the other modes use
    /// the standard light/dark background.
    private var appBackground: Color? {
        appearance == .custom ? Color(hex: colorBackground) : nil
    }

    /// Concrete light/dark for the whole app. Auto uses the clock; Custom picks
    /// the scheme that keeps text readable on the chosen background.
    private var resolvedScheme: ColorScheme {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .auto: return AppearanceMode.isNight(now) ? .dark : .light
        case .custom: return (Color(hex: colorBackground)?.isDark ?? false) ? .dark : .light
        }
    }

    private var palette: MetricPalette {
        MetricPalette.resolved(
            calories: colorCalories, protein: colorProtein, carbs: colorCarbs,
            fat: colorFat, water: colorWater
        )
    }

    var body: some View {
        ZStack {
            tabScreen(HomeView(), AppTab.today)
            tabScreen(MealListView(), AppTab.log)
            tabScreen(HistoryView(), AppTab.trends)
            tabScreen(SettingsView(), AppTab.settings)
        }
        // Custom bottom bar: shrunk tab container with the "+" beside it (only
        // on Today / Trends), so the "+" never sits on top of the tabs.
        .safeAreaInset(edge: .bottom) {
            AppTabBar(
                selection: $hub.selectedTab,
                showPlus: hub.selectedTab == AppTab.today || hub.selectedTab == AppTab.trends
            )
        }
        .tint(appAccent)
        .environment(\.appAccent, appAccent)
        .environment(\.appBackground, appBackground)
        .environment(\.metricPalette, palette)
        .preferredColorScheme(resolvedScheme)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .environmentObject(coordinator)
        .environmentObject(hub)
        // Siri / deep-link capture is modal; in-app capture is inline on Log.
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

    /// Keeps every tab alive (preserving its state) while showing only the
    /// selected one — so switching tabs doesn't reset in-progress capture, etc.
    @ViewBuilder
    private func tabScreen<V: View>(_ view: V, _ tab: Int) -> some View {
        view
            .opacity(hub.selectedTab == tab ? 1 : 0)
            .allowsHitTesting(hub.selectedTab == tab)
            .zIndex(hub.selectedTab == tab ? 1 : 0)
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
