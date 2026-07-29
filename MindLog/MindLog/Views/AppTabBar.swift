import SwiftUI

/// Tab indices (kept as Ints so AppStorage/deep links stay simple).
enum AppTab {
    static let journal = 0
    static let today = 1
    static let practice = 2
    static let trends = 3
    static let settings = 4
}

/// App-wide navigation hub: which tab is up, plus one-shot actions the "+"
/// menu (or a future Siri intent) hands to a tab to perform on arrival —
/// e.g. "open Journal already listening". Consumers read-and-clear.
@MainActor
final class AppHub: ObservableObject {
    static let shared = AppHub()

    @Published var selectedTab = AppTab.today
    /// Journal tab: start voice capture / open the typing editor on arrival.
    @Published var pendingJournalAction: JournalAction?
    /// Practice tab: open a session or the activity logger on arrival.
    @Published var pendingPracticeAction: PracticeAction?

    enum JournalAction { case voice, type }
    enum PracticeAction { case breathe, meditate, logActivity }

    func goVoiceJournal() {
        pendingJournalAction = .voice
        selectedTab = AppTab.journal
    }

    func goTypeJournal() {
        pendingJournalAction = .type
        selectedTab = AppTab.journal
    }

    func goPractice(_ action: PracticeAction) {
        pendingPracticeAction = action
        selectedTab = AppTab.practice
    }
}

/// A custom bottom bar so the tabs sit in a shrunk container on the left and the
/// "+" quick-actions menu sits *beside* them (not on top). The "+" only shows on
/// the tabs where it's useful (Today / Trends).
struct AppTabBar: View {
    /// Bottom padding for content pinned to the bottom of a NON-scrolling
    /// screen. The bar floats as a safe-area inset, which scroll views honor
    /// automatically — but plain views inside a NavigationStack don't inherit
    /// that inset, so they must clear the bar zone explicitly.
    static let clearance: CGFloat = 80

    @Binding var selection: Int
    var showPlus: Bool

    @EnvironmentObject private var hub: AppHub
    @Environment(\.appAccent) private var accent

    private struct TabItem { let tab: Int; let title: String; let icon: String }
    private let items: [TabItem] = [
        .init(tab: AppTab.journal, title: "Journal", icon: "text.book.closed"),
        .init(tab: AppTab.today, title: "Today", icon: "sun.max"),
        .init(tab: AppTab.practice, title: "Practice", icon: "figure.mind.and.body"),
        .init(tab: AppTab.trends, title: "Trends", icon: "chart.xyaxis.line"),
        .init(tab: AppTab.settings, title: "Settings", icon: "gearshape"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(items, id: \.tab) { item in
                    Button {
                        selection = item.tab
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.icon).font(.system(size: 17))
                            Text(item.title).font(.caption2)
                        }
                        .foregroundStyle(selection == item.tab ? accent : .secondary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            // Glassy, see-through backdrop (ultraThin) rather than an opaque
            // slab; the hairline stroke keeps the capsule readable over busy
            // content. Content scrolls beneath (the bar is a floating
            // safe-area inset), so the page shows through around and behind it.
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )

            if showPlus {
                quickMenu
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.2), value: showPlus)
    }

    private var quickMenu: some View {
        Menu {
            Button { hub.goVoiceJournal() } label: { Label("Voice entry", systemImage: "mic.fill") }
            Button { hub.goTypeJournal() } label: { Label("Type entry", systemImage: "keyboard") }
            Button { hub.goPractice(.logActivity) } label: { Label("Log activity", systemImage: "checkmark.circle") }
            Button { hub.goPractice(.breathe) } label: { Label("Breathe", systemImage: "wind") }
            Button { hub.goPractice(.meditate) } label: { Label("Meditate", systemImage: "figure.mind.and.body") }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(accent))
                .shadow(radius: 4, y: 2)
        }
        .accessibilityLabel("Quick actions")
    }
}
