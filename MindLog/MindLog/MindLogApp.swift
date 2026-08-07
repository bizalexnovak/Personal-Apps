import SwiftUI
import SwiftData
import Combine
import UIKit
import UserNotifications

@main
struct MindLogApp: App {
    init() {
        // Register the check-in category/actions and claim the delegate up
        // front so a tap on a mood button is handled even if it's the very
        // first thing that ever launches the process (background delivery).
        CheckInNotifications.registerCategories()
        UNUserNotificationCenter.current().delegate = CheckInNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(AppModelContainer.shared)
    }
}

struct ContentView: View {
    @StateObject private var hub = AppHub.shared
    @AppStorage(OnboardingKeys.completed) private var onboarded = false
    @State private var showWelcome = true
    @State private var keyboardVisible = false
    /// Ticks so Auto re-evaluates day/night across the 7am / 7pm boundaries.
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase

    // Reminder refresh needs today's live state; queried here once so the
    // scenePhase handler doesn't reach into child views.
    @Query private var entries: [JournalEntry]
    @Query private var logs: [ActivityLog]

    @AppStorage(ThemeKeys.appearance) private var appearanceRaw = AppearanceMode.dark.rawValue
    @AppStorage(ThemeKeys.appAccent) private var colorAppAccent = ""
    @AppStorage(ThemeKeys.background) private var colorBackground = ""
    @AppStorage(ThemeKeys.colorMood) private var colorMood = ""
    @AppStorage(ThemeKeys.colorScore) private var colorScore = ""
    @AppStorage(ThemeKeys.colorMinutes) private var colorMinutes = ""

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
        MetricPalette.resolved(mood: colorMood, score: colorScore, minutes: colorMinutes)
    }

    var body: some View {
        // The bar floats over the content as a bottom safe-area inset: scroll
        // views extend (and scroll) beneath it, showing through its glassy
        // material, while non-scrolling screens are laid out above it because
        // it shrinks their safe area.
        ZStack {
            tabScreen(JournalView(), AppTab.journal)
            tabScreen(HomeView(), AppTab.today)
            tabScreen(PracticeView(), AppTab.practice)
            tabScreen(TrendsView(), AppTab.trends)
            tabScreen(SettingsView(), AppTab.settings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
        // Re-evaluate the daily nudges as the app backgrounds/foregrounds so
        // "skip when already done today" reflects the latest entries.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .active {
                ReminderManager.refresh(
                    today: ReminderManager.todayState(entries: entries, logs: logs)
                )
            }
        }
        // Dismiss any open keyboard when moving between tabs.
        .onChange(of: hub.selectedTab) { _, _ in
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
        .environmentObject(hub)
        .sheet(isPresented: Binding(
            get: { !onboarded && !showWelcome },
            set: { if !$0 { onboarded = true } }
        )) {
            OnboardingView()
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
    /// selected one — so switching tabs doesn't reset an in-progress capture.
    @ViewBuilder
    private func tabScreen<V: View>(_ view: V, _ tab: Int) -> some View {
        view
            .opacity(hub.selectedTab == tab ? 1 : 0)
            .allowsHitTesting(hub.selectedTab == tab)
            .zIndex(hub.selectedTab == tab ? 1 : 0)
    }
}

/// A brief welcome/splash shown at launch. Auto-dismisses after a moment, or on
/// tap. Greets by time of day and first name: "Good evening, Alex / Good mind."
struct WelcomeView: View {
    var accent: Color
    @AppStorage(ProfileKeys.firstName) private var firstName = ""

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let name = firstName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent, accent.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "figure.mind.and.body")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)
                Text(greeting)
                    .font(.custom("Bradley Hand", size: 44).weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Good mind.")
                    .font(.custom("Bradley Hand", size: 30).weight(.bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding()
        }
        .contentShape(Rectangle())
    }
}
