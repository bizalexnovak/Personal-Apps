import SwiftUI
import SwiftData
import Combine
import UIKit

@main
struct FoobApp: App {
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
    @State private var showOnboarding = !ClaudeEndpoint.isConfigured
    // Skip the welcome splash when Siri launched us straight into an action.
    @State private var showWelcome = !CaptureHub.shared.hasPendingLaunchAction
    @State private var keyboardVisible = false
    /// Whether the orb menu is fanned open. Lives here rather than in the bar
    /// so switching screens can close it.
    @State private var menuOpen = false
    /// Ticks so Auto re-evaluates day/night across the 7am / 7pm boundaries.
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(ThemeKeys.appearance) private var appearanceRaw = AppearanceMode.dark.rawValue
    @AppStorage(ThemeKeys.background) private var colorBackground = ""

    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .dark }

    /// Fixed now. The accent and the five metric colours stopped being
    /// user-adjustable with the gold redesign — the ladder carries meaning in
    /// the Trends chart, so a chosen hue would break it. Colours stored by
    /// older builds are ignored rather than migrated; nothing reads those keys.
    private var appAccent: Color { MetricPalette.defaultAppAccent }

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

    var body: some View {
        // The orb and add bar float *over* the content rather than shrinking
        // its safe area, so each screen keeps its full height and manages its
        // own bottom clearance (OrbNavBar.clearance / .orbOnlyClearance).
        ZStack {
            tabScreen(HomeView(), AppTab.today)
            tabScreen(MealListView(), AppTab.log)
            tabScreen(HistoryView(), AppTab.trends)
            tabScreen(RecipesView(), AppTab.recipes)
            tabScreen(SettingsView(), AppTab.settings)
        }
        .ignoresSafeArea(.container, edges: .top) // let screens go under the status bar
        // Painted once at the root rather than per screen: the screens are
        // transparent over it, so Custom mode's colour reaches all of them.
        .background((appBackground ?? Lux.ground).ignoresSafeArea())
        .overlay(alignment: .bottom) {
            // Hidden while a keyboard is up so it doesn't collide with the
            // keyboard toolbar; it returns when the keyboard dismisses.
            if !keyboardVisible {
                OrbNavBar(
                    selection: $hub.selectedTab,
                    // Only Today carries the add bar. Micros is a mode of the
                    // Today screen, so it inherits this too.
                    showAddBar: hub.selectedTab == AppTab.today,
                    open: $menuOpen
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
        .environment(\.metricPalette, .default)
        .preferredColorScheme(resolvedScheme)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        // Seed the starter recipe library and food database once, then sync
        // this device's contributions with the community database (no-op for
        // direct-key installs with no proxy configured).
        .task {
            let context = AppModelContainer.shared.mainContext
            RecipeSeed.seedIfNeeded(in: context)
            CustomFoodSeed.seedIfNeeded(in: context)
            await CommunitySync.syncNow(context: context)
        }
        // Re-evaluate the end-of-day reminder as the app backgrounds/foregrounds
        // so it reflects the latest totals and time of day.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .active {
                ReminderManager.refresh()
            }
        }
        // Dismiss any open keyboard when moving between screens, and close the
        // orb menu behind a destination reached some other way (Siri, the add
        // bar, a deep link).
        .onChange(of: hub.selectedTab) { _, _ in
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
            menuOpen = false
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
                WelcomeView()
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
            Lux.vignette.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Lux.goldFill)

                Text("FOOB")
                    .font(Lux.smallcaps(8))
                    .tracking(4)
                    .foregroundStyle(Lux.goldLabel.opacity(0.7))
                    .padding(.top, 2)

                // Long greetings ("Good afternoon, Alexander") get the smaller
                // engraved size so they stay on one line.
                Text(greeting.uppercased())
                    .font(Lux.title(greeting.count > 16 ? 22 : 27))
                    .tracking(3)
                    .multilineTextAlignment(.center)
                    .engravedFill()

                LuxDiamondRule().padding(.vertical, 2)

                Text("Good health.")
                    .font(Lux.serifItalic(20))
                    .foregroundStyle(Lux.cream.opacity(0.6))
            }
            .padding(.horizontal, Lux.hPad)
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
