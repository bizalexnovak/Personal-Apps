import SwiftUI

/// The gold-on-emerald design language: palette, type, and the handful of
/// shapes every screen is assembled from.
///
/// Values come from the design handoff and are treated as final — screens
/// reference `Lux.…` rather than inlining hex, so a change here reaches the
/// whole app. Sizes are logical points; the prototype was drawn at 402×874
/// (iPhone 16 Pro), where its px map 1:1 to pt.
enum Lux {

    // MARK: - Ground

    /// Screen background.
    static let ground = Color(hex: "#0f2b21")!
    /// Dimmed backdrop behind sheets and the orb menu scrim.
    static let deep = Color(hex: "#0a1d16")!
    /// Card and chart panel fill.
    static let panel = Color(hex: "#173629")!
    /// Modal sheet background.
    static let sheet = Color(hex: "#123528")!
    /// Backdrop behind a live camera feed.
    static let cameraGround = Color(hex: "#0a1710")!

    // MARK: - Gold ladder
    //
    // Five steps from champagne to bronze. Charts and rings walk the ladder so
    // series stay distinguishable without leaving the palette; `goldLabel` is
    // the flat gold used for text furniture rather than data.

    static let goldBright = Color(hex: "#e8d2a0")!
    static let goldMidBright = Color(hex: "#d4b475")!
    static let gold = Color(hex: "#c9a55e")!
    static let goldDeep = Color(hex: "#a3814a")!
    static let bronze = Color(hex: "#8a6d3f")!
    static let goldLabel = Color(hex: "#b3925a")!

    // MARK: - Ink

    static let cream = Color(hex: "#efe7d8")!

    /// Warning / low-confidence. Replaces the old yellow; oxblood stays
    /// reserved for destructive actions.
    static let ember = Color(hex: "#c9763f")!

    // MARK: - Lines and tracks

    /// Row separators.
    static let hairline = goldLabel.opacity(0.22)
    /// Card and panel outlines.
    static let panelBorder = goldLabel.opacity(0.28)
    /// Ghost buttons, chips, toggles in their off state.
    static let controlBorder = goldLabel.opacity(0.4)
    /// Unfilled portion of a bar or gauge.
    static let track = cream.opacity(0.10)

    // MARK: - Gradients

    /// Every gold fill — orbs, coins, pills, slider thumbs, gauge fills.
    static let goldFill = LinearGradient(
        colors: [Color(hex: "#c6a468")!, Color(hex: "#ab8a52")!],
        startPoint: .top, endPoint: .bottom)

    /// Horizontal variant for progress bars and gauges, which fill left to
    /// right rather than top to bottom.
    static let goldFillH = LinearGradient(
        colors: [Color(hex: "#ab8a52")!, Color(hex: "#c6a468")!],
        startPoint: .leading, endPoint: .trailing)

    /// Title text fill — brighter at the top so letterforms read as struck
    /// into the surface rather than printed on it.
    static let engraved = LinearGradient(
        stops: [.init(color: Color(hex: "#e3cb96")!, location: 0),
                .init(color: Color(hex: "#b3925a")!, location: 0.48),
                .init(color: Color(hex: "#7d6238")!, location: 1)],
        startPoint: .top, endPoint: .bottom)

    /// Welcome-splash vignette.
    static let vignette = RadialGradient(
        colors: [Color(hex: "#17402f")!, ground],
        center: .center, startRadius: 0, endRadius: 380)

    /// Scrim under the bottom of scrolling screens so content fades out rather
    /// than colliding with the add bar.
    static let bottomScrim = LinearGradient(
        colors: [ground.opacity(0), ground.opacity(0.96)],
        startPoint: .top, endPoint: .bottom)

    // MARK: - Shape

    /// Horizontal padding on every screen.
    static let hPad: CGFloat = 22
    /// Panels are nearly square-cornered; only capsules are round.
    static let panelRadius: CGFloat = 4
    static let orbSize: CGFloat = 54
    static let menuOrbSize: CGFloat = 46

    static let floatingShadow = (color: Color.black.opacity(0.5), radius: CGFloat(15), y: CGFloat(10))
    static let buttonShadow = (color: Color.black.opacity(0.4), radius: CGFloat(11), y: CGFloat(8))
}

// MARK: - Type

extension Lux {
    /// Bundled faces, by PostScript name. Registered through `UIAppFonts` in
    /// project.yml; the files live in Resources/Fonts.
    enum Face {
        static let engraved = "CinzelDecorative-Bold"
        static let serif = "CormorantGaramond-Regular"
        static let serifMedium = "CormorantGaramond-Medium"
        static let serifItalic = "CormorantGaramond-Italic"
        static let serifMediumItalic = "CormorantGaramond-MediumItalic"
    }

    /// Cinzel, for screen titles only. Always paired with `.engravedFill()`.
    static func title(_ size: CGFloat = 24) -> Font {
        .custom(Face.engraved, size: size)
    }

    /// Cormorant, for values and row titles. Weight 500 reads as the emphasis
    /// step; there is no bold in this language.
    static func serif(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? Face.serifMedium : Face.serif, size: size)
    }

    /// Cormorant italic, for captions, subtitles, and anything conversational.
    static func serifItalic(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? Face.serifMediumItalic : Face.serifItalic, size: size)
    }

    /// System sans in uppercase — section headers, eyebrows, field labels,
    /// units. Always letterspaced; the tracking is what makes it read as
    /// smallcaps rather than shouting.
    static func smallcaps(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
}

// MARK: - Text treatments

extension View {
    /// Gradient fill plus the two hairline shadows that give titles their
    /// struck-metal edge: a dark drop below, a warm highlight above.
    func engravedFill() -> some View {
        self
            .foregroundStyle(Lux.engraved)
            .shadow(color: .black.opacity(0.7), radius: 0, x: 0, y: 1)
            .shadow(color: Color(hex: "#ffecbe")!.opacity(0.22), radius: 0, x: 0, y: -0.5)
    }

    /// Floating element shadow (orbs, add bar, medallion).
    func luxFloating() -> some View {
        shadow(color: Lux.floatingShadow.color,
               radius: Lux.floatingShadow.radius, x: 0, y: Lux.floatingShadow.y)
    }

    /// Panel chrome: near-square corners, 1px gold border, emerald fill.
    func luxPanel(padding: CGFloat = 13) -> some View {
        self
            .padding(padding)
            .background(Lux.panel)
            .clipShape(RoundedRectangle(cornerRadius: Lux.panelRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Lux.panelRadius)
                    .stroke(Lux.panelBorder, lineWidth: 1))
    }

    /// A content row in a ledger: vertical padding and a hairline underneath.
    /// Lists in this language are ruled, never boxed.
    func luxRow(vertical: CGFloat = 13) -> some View {
        VStack(spacing: 0) {
            self.padding(.vertical, vertical)
            Rectangle().fill(Lux.hairline).frame(height: 1)
        }
    }
}

/// An engraved screen title, with the FOOB eyebrow above it.
struct LuxTitle: View {
    let text: String
    var eyebrow: Bool = true
    var size: CGFloat = 24

    var body: some View {
        VStack(spacing: 6) {
            if eyebrow {
                Text("FOOB")
                    .font(Lux.smallcaps(8))
                    .tracking(4)
                    .foregroundStyle(Lux.goldLabel.opacity(0.7))
            }
            Text(text)
                .font(Lux.title(size))
                .tracking(3)
                .engravedFill()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Uppercase gold section header — "CALORIES", "MEALS", "RECOMMENDED FOR NOW".
struct LuxSectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Lux.smallcaps(9))
            .tracking(2.5)
            .foregroundStyle(Lux.goldLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Two gold rules flanking a rotated square. Used on the welcome splash.
struct LuxDiamondRule: View {
    var width: CGFloat = 54
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Lux.goldLabel.opacity(0.6)).frame(width: width, height: 1)
            Rectangle().fill(Lux.goldLabel).frame(width: 6, height: 6).rotationEffect(.degrees(45))
            Rectangle().fill(Lux.goldLabel.opacity(0.6)).frame(width: width, height: 1)
        }
    }
}

// MARK: - Controls

/// Primary action. Gold gradient with emerald text when live; a ghost outline
/// while disabled, so enabling something pours gold into it.
struct GoldCapsule: ButtonStyle {
    var enabled: Bool = true
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Lux.smallcaps(10))
            .tracking(2.5)
            .foregroundStyle(enabled ? Lux.ground : Lux.cream.opacity(0.35))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if enabled {
                    Capsule().fill(Lux.goldFill)
                } else {
                    Capsule().stroke(Lux.controlBorder, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeInOut(duration: 0.25), value: enabled)
    }
}

/// Secondary action: hairline outline, no fill. `gold` picks the text colour.
struct GhostCapsule: ButtonStyle {
    var gold: Bool = false
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Lux.smallcaps(9))
            .tracking(2)
            .foregroundStyle(gold ? Lux.gold : Lux.cream.opacity(0.8))
            .padding(.horizontal, 18)
            .frame(height: height)
            .background(Capsule().stroke(Lux.controlBorder, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The typographic switcher used for MACROS/MICROS, LOSE/MAINTAIN/GAIN, the
/// capture-mode row, and the Trends range picker: no track, no pill — the
/// active item is cream over a gold underline.
struct LuxSwitcher<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var spacing: CGFloat = 18
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(options, id: \.value) { option in
                let active = option.value == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(Lux.smallcaps(size))
                        .tracking(2)
                        .foregroundStyle(active ? Lux.cream : Lux.cream.opacity(0.45))
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(active ? Lux.goldLabel : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Text field with no box — an italic serif placeholder over a gold rule.
struct LuxUnderlinedField: View {
    let placeholder: String
    @Binding var text: String
    var size: CGFloat = 21
    /// API keys and other secrets mask as you type.
    var secure: Bool = false
    var autocapitalization: TextInputAutocapitalization = .never

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(Lux.serifItalic(size))
                        .foregroundStyle(Lux.cream.opacity(0.35))
                }
                Group {
                    if secure {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                    }
                }
                .font(Lux.serif(size))
                .foregroundStyle(Lux.cream)
                .tint(Lux.gold)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
            }
            Rectangle().fill(Lux.goldLabel.opacity(0.5)).frame(height: 1)
        }
    }
}

/// Small uppercase label above a field or beside a value.
struct LuxFieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Lux.smallcaps(8))
            .tracking(2)
            .foregroundStyle(Lux.cream.opacity(0.45))
    }
}

/// Italic serif explanatory text — the voice this design uses for anything
/// conversational, in place of a system footnote.
struct LuxNote: View {
    let text: String
    var size: CGFloat = 13
    init(_ text: String, size: CGFloat = 13) {
        self.text = text
        self.size = size
    }
    var body: some View {
        Text(text)
            .font(Lux.serifItalic(size))
            .foregroundStyle(Lux.cream.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Sheet chrome shared by Onboarding and the typed-entry sheet: emerald
/// ground, a gold top border, and a gold grab handle.
struct LuxSheet<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Lux.goldLabel.opacity(0.4))
                .frame(width: 40, height: 4)
                .padding(.top, 10)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Lux.sheet.ignoresSafeArea())
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Lux.goldLabel.opacity(0.3))
                .frame(height: 1)
        }
        // Paints the presentation surface itself, not just our content, so the
        // system's default sheet material doesn't show at the rounded corners.
        .presentationBackground(Lux.sheet)
    }
}

// MARK: - Metric colours

extension Metric {
    /// Today's ring colour. The rings show four metrics, not five — calories
    /// is the bar above them — so the ladder shifts up a step and protein
    /// takes champagne. Deliberately distinct from `luxColor`.
    var luxRingColor: Color {
        switch self {
        case .calories: return Lux.goldBright
        case .protein:  return Lux.goldBright
        case .carbs:    return Lux.gold
        case .fat:      return Lux.goldDeep
        case .water:    return Lux.bronze
        }
    }
}

// MARK: - List chrome

extension View {
    /// Strips a List's or Form's system chrome so ruled rows can be drawn on
    /// the emerald ground. Applied to the container; rows also need
    /// `luxRowChrome()`.
    func luxList() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .luxScreen()
    }

    /// Clears one row's background and separator so `luxRow` can draw the
    /// hairline instead.
    func luxRowChrome(inset: CGFloat = Lux.hPad) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset))
    }
}

/// A label-left / value-right row on a hairline — the shape most of Settings
/// and the editors are built from.
struct LuxValueRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Lux.smallcaps(9))
                .tracking(2)
                .foregroundStyle(Lux.cream.opacity(0.45))
            Spacer()
            value
        }
        .luxRow(vertical: 11)
    }
}

/// A navigable row: serif title, gold chevron. Settings is a stack of these.
struct LuxNavRow: View {
    let title: String
    var detail: String?
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Lux.serif(size))
                .foregroundStyle(Lux.cream)
            Spacer()
            if let detail {
                Text(detail)
                    .font(Lux.serifItalic(15))
                    .foregroundStyle(Lux.cream.opacity(0.45))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Lux.goldLabel)
        }
        .contentShape(Rectangle())
        .luxRow(vertical: 13)
    }
}

/// A screen header: optional leading/trailing controls, engraved title, and an
/// italic subtitle. Every destination in the app opens with one.
struct LuxHeader<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var eyebrow: Bool = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                leading
                Spacer()
                trailing
            }
            .frame(minHeight: 20)
            .padding(.bottom, 8)

            LuxTitle(text: title, eyebrow: eyebrow)

            if let subtitle {
                Text(subtitle)
                    .font(Lux.serifItalic(15))
                    .foregroundStyle(Lux.cream.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, Lux.hPad)
        .padding(.top, 64)
    }
}

extension LuxHeader where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, eyebrow: Bool = true) {
        self.init(title: title, subtitle: subtitle, eyebrow: eyebrow,
                  leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// A back chevron for pushed destinations, which hide the system nav bar.
struct LuxBackButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Lux.cream)
        }
        .accessibilityLabel("Back")
    }
}
