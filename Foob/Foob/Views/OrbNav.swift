import SwiftUI

/// The gold orb that replaced the five-tab bar.
///
/// Tapping it dims the screen and fans five smaller orbs up the right edge,
/// each labelled with a name chip. Navigation is a deliberate act rather than
/// permanent furniture, which buys the screens their full height back — the
/// only thing that stays pinned is the add bar on Today and Micros, because
/// logging a meal is the one action worth a permanent target.
struct OrbNavBar: View {
    @Binding var selection: Int
    /// Today and Micros carry the cream add bar; every other screen shows the
    /// orb alone.
    var showAddBar: Bool

    @Binding var open: Bool

    @EnvironmentObject private var hub: CaptureHub

    /// Bottom padding a screen's scrolling content needs so the last row
    /// clears the floating controls.
    static let clearance: CGFloat = 120
    /// Same, for screens showing the orb without an add bar.
    static let orbOnlyClearance: CGFloat = 104

    private struct Destination {
        let tab: Int
        let label: String
        let icon: String
    }

    /// Top to bottom, so the current screen's neighbours sit nearest the thumb.
    private let destinations: [Destination] = [
        .init(tab: AppTab.today, label: "TODAY", icon: "chart.bar.fill"),
        .init(tab: AppTab.log, label: "LOG", icon: "fork.knife"),
        .init(tab: AppTab.trends, label: "TRENDS", icon: "chart.xyaxis.line"),
        .init(tab: AppTab.recipes, label: "RECIPES", icon: "book.closed"),
        .init(tab: AppTab.settings, label: "SETTINGS", icon: "gearshape"),
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if open {
                scrim
                menu
            }
            bottomRow
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: open)
    }

    // MARK: - Scrim

    private var scrim: some View {
        Rectangle()
            .fill(Color(hex: "#081611")!.opacity(0.74))
            .background(.ultraThinMaterial.opacity(0.4))
            .ignoresSafeArea()
            .transition(.opacity)
            .onTapGesture { open = false }
            .accessibilityLabel("Close menu")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Fanned menu

    private var menu: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(Array(destinations.enumerated()), id: \.element.tab) { index, destination in
                menuRow(destination)
                    // Stagger from the bottom of the stack up, so the fan
                    // appears to spring out of the orb rather than land as a
                    // block. ~40ms apart, matching the handoff.
                    .transition(
                        .scale(scale: 0.6, anchor: .bottomTrailing)
                        .combined(with: .opacity)
                        .animation(
                            .spring(response: 0.32, dampingFraction: 0.74)
                            .delay(Double(destinations.count - 1 - index) * 0.04))
                    )
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 104)
    }

    private func menuRow(_ destination: Destination) -> some View {
        let current = destination.tab == selection
        return HStack(spacing: 10) {
            Text(destination.label)
                .font(Lux.smallcaps(8.5))
                .tracking(2)
                .foregroundStyle(Lux.cream)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Lux.ground.opacity(0.9)))
                .overlay(Capsule().stroke(Lux.goldLabel.opacity(0.35), lineWidth: 1))

            Image(systemName: destination.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Lux.ground)
                .frame(width: Lux.menuOrbSize, height: Lux.menuOrbSize)
                .background(Circle().fill(Lux.goldFill))
                .overlay(
                    Circle().stroke(current ? Lux.cream : .clear, lineWidth: 2))
                .shadow(color: .black.opacity(0.45), radius: 9, y: 6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selection = destination.tab
            open = false
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(destination.label.capitalized)
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Add bar + orb

    private var bottomRow: some View {
        HStack(spacing: 10) {
            if showAddBar { addBar }
            orb
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    private var addBar: some View {
        HStack(spacing: 9) {
            // Tapping anywhere but the mic opens voice capture without
            // starting it; the mic starts listening immediately.
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Lux.cream)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Lux.ground))

            Text("Log a meal")
                .font(Lux.serifItalic(15))
                .foregroundStyle(Lux.ground.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                hub.goVoice()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Lux.ground)
                    .padding(.trailing, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start listening")
        }
        .padding(.horizontal, 6)
        .frame(height: 48)
        .background(Capsule().fill(Lux.cream))
        .luxFloating()
        .contentShape(Capsule())
        .onTapGesture {
            hub.logMode = .voice
            hub.selectedTab = AppTab.log
        }
        .accessibilityLabel("Log a meal")
    }

    private var orb: some View {
        Button {
            open.toggle()
        } label: {
            Image(systemName: open ? "xmark" : "line.3.horizontal")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Lux.ground)
                .frame(width: Lux.orbSize, height: Lux.orbSize)
                .background(Circle().fill(Lux.goldFill))
                .overlay(Circle().stroke(Lux.cream.opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 15, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(open ? "Close menu" : "Menu")
    }
}

extension View {
    /// Floats the orb (and, on Today and Micros, the add bar) over a screen.
    /// Applied once around the whole tab stack rather than per screen, so the
    /// menu animates over whatever is showing.
    func luxOrbNav(selection: Binding<Int>, open: Binding<Bool>, showAddBar: Bool) -> some View {
        overlay(alignment: .bottom) {
            OrbNavBar(selection: selection, showAddBar: showAddBar, open: open)
        }
    }

    /// Emerald ground behind a screen, edge to edge.
    func luxScreen() -> some View {
        background(Lux.ground.ignoresSafeArea())
    }
}
