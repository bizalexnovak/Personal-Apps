import SwiftUI
import UIKit

/// Shared building blocks for the capture→review flow, so the Siri `CaptureView`
/// (modal) and the Log tab (inline) render exactly the same pieces.

/// The mic medallion — identical disc and position whether idle or actively
/// listening, so tapping to start doesn't move or change it. Only the halos and
/// the caption below react. Idle breathes slowly; listening speeds up and
/// swells with the live audio level.
struct MicGraphic: View {
    /// nil = idle; non-nil = listening. Either way it keeps a gentle pulse; a
    /// non-nil level adds live audio reactivity on top.
    var audioLevel: Double?

    /// Diameter of the gold disc. The halos and the caption offset are measured
    /// from this, so the medallion scales as one object.
    static let discSize: CGFloat = 104
    /// Distance from the medallion's centre down to its caption.
    static let captionOffset: CGFloat = 104

    var body: some View {
        // Time-driven pulse (TimelineView) instead of a repeatForever state
        // animation: audio-level updates were cancelling that animation after
        // a moment. Deriving the pulse from the clock every frame can't stop.
        TimelineView(.animation) { context in
            let listening = audioLevel != nil
            let period = listening ? 1.2 : 2.6
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * 2 * .pi / period) + 1) / 2 // 0…1
            let level = CGFloat(audioLevel ?? 0)

            // Idle breathes between 0.94–1.08 and 0.97–1.04. Listening starts
            // wider and rides the audio level on top.
            let outerScale = listening
                ? 1.02 + 0.32 * pulse + level * 0.5
                : 0.94 + 0.14 * pulse
            let midScale = listening
                ? 1.00 + 0.16 * pulse + level * 0.3
                : 0.97 + 0.07 * pulse

            ZStack {
                Circle().fill(Lux.gold.opacity(0.10))
                    .frame(width: 180, height: 180)
                    .scaleEffect(outerScale)
                Circle().fill(Lux.gold.opacity(0.16))
                    .frame(width: 134, height: 134)
                    .scaleEffect(midScale)
                Circle()
                    .fill(Lux.goldFill)
                    .frame(width: Self.discSize, height: Self.discSize)
                    .overlay(Circle().stroke(Lux.cream.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 17, y: 12)
                Image(systemName: "mic.fill")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Lux.ground)
            }
        }
        .frame(width: 184, height: 184)
    }
}

/// Active listening: the same medallion in the same place, transcript streaming
/// in beneath it. Used by the Siri modal and by the post-scan naming step.
struct ListeningView: View {
    var audioLevel: Double
    var transcript: String
    var prompt: String
    var subtitle: String?
    var showSkip: Bool = false
    /// Bottom padding under the Done/Skip buttons. The inline Log tab passes
    /// the floating orb's clearance; the modal capture keeps the default.
    var bottomClearance: CGFloat = 24
    var onDone: () -> Void
    var onSkip: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let micY = geo.size.height * 0.30

            MicGraphic(audioLevel: audioLevel)
                .position(x: midX, y: micY)

            VStack(spacing: 10) {
                if let subtitle {
                    Text(subtitle)
                        .font(Lux.serifItalic(15))
                        .foregroundStyle(Lux.cream.opacity(0.45))
                        .multilineTextAlignment(.center)
                }
                Text(transcript.isEmpty ? prompt : "\u{201C}\(transcript)\u{201D}")
                    .font(Lux.serifItalic(transcript.isEmpty ? 17 : 22))
                    .foregroundStyle(Lux.cream.opacity(transcript.isEmpty ? 0.55 : 1))
                    .multilineTextAlignment(.center)
                    .animation(.default, value: transcript)
            }
            .frame(maxWidth: max(0, geo.size.width - 2 * Lux.hPad))
            .position(x: midX, y: micY + MicGraphic.captionOffset + 8)

            VStack(spacing: 14) {
                Spacer()
                Button("DONE", action: onDone)
                    .buttonStyle(GoldCapsule())
                    .frame(maxWidth: 220)
                if showSkip {
                    Button("SKIP — NAME IT LATER", action: onSkip)
                        .buttonStyle(GhostCapsule())
                }
            }
            .padding(.horizontal, Lux.hPad)
            .padding(.bottom, bottomClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .luxScreen()
    }
}

/// Keyboard accessory bar with one "hide keyboard" button — the standard
/// keyboard-with-chevron icon — shared by every screen that shows a keyboard.
/// Dismissal resigns the first responder globally, so no per-screen FocusState
/// wiring is needed.
struct KeyboardDismissBar: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                    )
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide keyboard")
            }
        }
    }
}

extension View {
    /// Adds the shared hide-keyboard accessory bar above the keyboard.
    func keyboardDismissBar() -> some View { modifier(KeyboardDismissBar()) }
}

/// The wait while parsing / reading a label / estimating a dish. A hairline
/// ring with one rotating arc, rather than a system spinner.
///
/// The status text always comes from MealCaptureCoordinator.WorkKind — the
/// single operation→string mapping — so different screens can't drift apart.
struct AnalyzingView: View {
    var text: String

    var body: some View {
        VStack(spacing: 22) {
            TimelineView(.animation) { context in
                let angle = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 2.8) / 2.8 * 360
                ZStack {
                    Circle()
                        .stroke(Lux.gold.opacity(0.18), lineWidth: 1)
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(Lux.gold, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                        .rotationEffect(.degrees(angle))
                    Image(systemName: "fork.knife")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Lux.goldFill)
                }
                .frame(width: 104, height: 104)
            }

            VStack(spacing: 8) {
                Text(text)
                    .font(Lux.serifItalic(18))
                    .foregroundStyle(Lux.cream.opacity(0.8))
                    .multilineTextAlignment(.center)
                Text("THEN MATCHING EACH ITEM IN THE FOOD DATABASE")
                    .font(Lux.smallcaps(8))
                    .tracking(2)
                    .foregroundStyle(Lux.cream.opacity(0.35))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Lux.hPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .luxScreen()
    }
}

/// A permission / transient-error state with an action button.
struct CaptureProblemView<Action: View>: View {
    var message: String
    var systemImage: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Lux.goldLabel)
            Text(message)
                .font(Lux.serifItalic(17))
                .foregroundStyle(Lux.cream.opacity(0.7))
                .multilineTextAlignment(.center)
            action()
        }
        .padding(.horizontal, Lux.hPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .luxScreen()
    }
}

// MARK: - Camera framing

/// Four corner brackets marking the capture area — the camera modes' shared
/// reticle. Legs are drawn rather than stroked as a dashed rectangle so the
/// corners stay crisp at any frame size.
struct CornerBrackets: View {
    var size: CGSize
    var leg: CGFloat = 34
    var lineWidth: CGFloat = 2
    var color: Color = Lux.gold

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { corner in
                bracket
                    .rotationEffect(.degrees(Double(corner) * 90))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// One top-left bracket; the other three are rotations of it. Rotating a
    /// non-square frame needs the corner drawn inside a square, so it is laid
    /// out against the larger dimension and clipped by the parent frame.
    private var bracket: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: leg))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: leg, y: 0))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Live label scanner with an auto-capture reticle, plus a denied state.
struct ScannerScreen: View {
    var onCapture: (Data) -> Void
    @State private var denied = false

    var body: some View {
        if denied {
            CaptureProblemView(
                message: "Foob needs camera access to scan labels. Enable it in Settings.",
                systemImage: "camera.fill"
            ) {
                Button("OPEN SETTINGS") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(GhostCapsule(gold: true))
            }
        } else {
            ZStack {
                Lux.cameraGround.ignoresSafeArea()
                LiveLabelScannerView(onCapture: onCapture, onDenied: { denied = true })
                    .ignoresSafeArea()
                VStack(spacing: 18) {
                    Spacer()
                    ZStack {
                        CornerBrackets(size: CGSize(width: 250, height: 320))
                        ScanLine(height: 320)
                    }
                    .frame(width: 250, height: 320)
                    Text("Frame the nutrition label — it captures on its own.")
                        .font(Lux.serifItalic(15))
                        .foregroundStyle(Lux.cream.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.7), radius: 6)
                    Spacer()
                }
                .padding(.horizontal, Lux.hPad)
            }
        }
    }
}

/// The gold line sweeping the scan frame. Purely decorative — capture is
/// driven by the recognizer, not by where the line happens to be.
struct ScanLine: View {
    var height: CGFloat
    var period: Double = 2.4

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period
            // Triangle wave: down the frame, then back up.
            let travel = t < 0.5 ? t * 2 : (1 - t) * 2
            LinearGradient(
                colors: [Lux.gold.opacity(0), Lux.gold, Lux.gold.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 2)
            .shadow(color: Lux.gold.opacity(0.7), radius: 5)
            .offset(y: (travel - 0.5) * (height - 8))
        }
    }
}
