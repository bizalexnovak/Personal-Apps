import SwiftUI

/// A custom bottom bar so the tabs sit in a shrunk container on the left and the
/// "+" capture menu sits *beside* them (not on top). The "+" only shows on the
/// tabs where it's useful (Today / Trends).
struct AppTabBar: View {
    @Binding var selection: Int
    var showPlus: Bool

    @EnvironmentObject private var hub: CaptureHub
    @Environment(\.appAccent) private var accent

    private struct TabItem { let tab: Int; let title: String; let icon: String }
    private let items: [TabItem] = [
        .init(tab: AppTab.log, title: "Log", icon: "fork.knife"),
        .init(tab: AppTab.today, title: "Today", icon: "chart.bar.fill"),
        .init(tab: AppTab.trends, title: "Trends", icon: "chart.xyaxis.line"),
        .init(tab: AppTab.recipes, title: "Recipes", icon: "book.closed"),
        .init(tab: AppTab.settings, title: "Settings", icon: "gearshape"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(items, id: \.tab) { item in
                    Button {
                        selection = item.tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.icon).font(.system(size: 19))
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
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))

            if showPlus {
                captureMenu
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.2), value: showPlus)
    }

    private var captureMenu: some View {
        Menu {
            Button { hub.goVoice() } label: { Label("Voice", systemImage: "mic.fill") }
            Button { hub.goScan() } label: { Label("Scan", systemImage: "doc.viewfinder") }
            Button { hub.goDish() } label: { Label("AI", systemImage: "sparkles") }
            Button { hub.goType() } label: { Label("Type", systemImage: "keyboard") }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(accent))
                .shadow(radius: 4, y: 2)
        }
        .accessibilityLabel("Log a meal")
    }
}
