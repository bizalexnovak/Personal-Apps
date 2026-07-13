import SwiftUI
import SwiftData
import Combine
import UIKit

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
    @StateObject private var hub = CaptureHub.shared
    @ObservedObject private var pendingStore = PendingMealStore.shared
    @State private var showOnboarding = KeychainService.get(.claudeAPIKey) == nil
    // Skip the welcome splash when Siri launched us straight into an action.
    @State private var showWelcome = !CaptureHub.shared.hasPendingLaunchAction
    @State private var keyboardVisible = false
    /// Ticks so Auto re-evaluates day/night across the 7am / 7pm boundaries.
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase

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
        // A plain VStack (content above, custom bar below) so the tabs sit in a
        // shrunk container with the "+" beside them AND non-scrolling content
        // (the Log capture screen) stays above the bar instead of behind it.
        VStack(spacing: 0) {
            ZStack {
                tabScreen(HomeView(), AppTab.today)
                tabScreen(MealListView(), AppTab.log)
                tabScreen(HistoryView(), AppTab.trends)
                tabScreen(SettingsView(), AppTab.settings)
            }
            .ignoresSafeArea(.container, edges: .top) // let screens go under the status bar
            // Hide the tab bar while a keyboard is up so it doesn't collide with
            // the keyboard's toolbar; it returns when the keyboard dismisses.
            if !keyboardVisible {
                AppTabBar(
                    selection: $hub.selectedTab,
                    showPlus: hub.selectedTab == AppTab.today || hub.selectedTab == AppTab.trends
                )
                .transition(.move(edge: .bottom))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .tint(appAccent)
        .environment(\.appAccent, appAccent)
        .environment(\.appBackground, appBackground)
        .environment(\.metricPalette, palette)
        .preferredColorScheme(resolvedScheme)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        // Re-evaluate the end-of-day reminder as the app backgrounds/foregrounds
        // so it reflects the latest totals and time of day.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .active {
                ReminderManager.refresh()
            }
        }
        // Dismiss any open keyboard when moving between tabs.
        .onChange(of: hub.selectedTab) { _, _ in
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
        .environmentObject(coordinator)
        .environmentObject(hub)
        // Siri / deep-link capture is modal; in-app capture is inline on Log.
        .fullScreenCover(item: $pendingStore.request) { request in
            CaptureView(mode: request.mode)
                .environmentObject(coordinator)
        }
        .sheet(isPresented: Binding(
            get: { showOnboarding && !showWelcome },
            set: { showOnboarding = $0 }
        )) {
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
        .overlay {
            if showWelcome {
                WelcomeView(accent: appAccent)
                    .transition(.opacity)
                    .onTapGesture { dismissWelcome() }
                    .task {
                        try? await Task.sleep(for: .seconds(1.8))
                        dismissWelcome()
                    }
                    .zIndex(10)
            }
        }
    }

    private func dismissWelcome() {
        guard showWelcome else { return }
        withAnimation(.easeOut(duration: 0.35)) { showWelcome = false }
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

/// A brief welcome/splash shown at launch. Auto-dismisses after a moment, or on
/// tap. Greets by time of day and first name: "Good morning, Alex / Good health."
struct WelcomeView: View {
    var accent: Color
    @AppStorage(ProfileKeys.firstName) private var firstName = ""
    @AppStorage(ProfileKeys.name) private var legacyName = ""

    private var first: String {
        let f = firstName.trimmingCharacters(in: .whitespaces)
        if !f.isEmpty { return f }
        return legacyName.split(separator: " ").first.map(String.init) ?? ""
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        return first.isEmpty ? part : "\(part), \(first)"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent, accent.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)
                Text(greeting)
                    .font(.custom("Bradley Hand", size: 44).weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Good health.")
                    .font(.custom("Bradley Hand", size: 30).weight(.bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding()
        }
        .contentShape(Rectangle())
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
    /// Legacy single-field name; migrated into first/last on Profile open.
    static let name = "profile_name"
    static let firstName = "profile_first_name"
    static let lastName = "profile_last_name"
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
