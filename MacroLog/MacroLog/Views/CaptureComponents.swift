import SwiftUI
import UIKit

/// Shared building blocks for the capture→review flow, so the Siri `CaptureView`
/// (modal) and the Log tab (inline) render exactly the same pieces.

/// The mic graphic — identical icon and position whether idle or actively
/// listening, so tapping to start doesn't move or change it. Idle gives a gentle
/// continuous pulse; listening pulses with the live audio level.
struct MicGraphic: View {
    @Environment(\.appAccent) private var accent
    /// nil = idle; non-nil = listening. Either way it keeps a gentle pulse; a
    /// non-nil level adds live audio reactivity on top.
    var audioLevel: Double?

    var body: some View {
        // Time-driven pulse (TimelineView) instead of a repeatForever state
        // animation: audio-level updates were cancelling that animation after
        // a moment. Deriving the pulse from the clock every frame can't stop.
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * 2 * .pi / 2.2) + 1) / 2 // 0…1 over ~2.2 s
            let level = CGFloat(audioLevel ?? 0)
            let outerScale = 0.94 + 0.14 * pulse + level * 0.5
            let midScale = 0.97 + 0.07 * pulse + level * 0.3

            ZStack {
                Circle().fill(accent.opacity(0.15))
                    .frame(width: 180, height: 180)
                    .scaleEffect(outerScale)
                Circle().fill(accent.opacity(0.22))
                    .frame(width: 132, height: 132)
                    .scaleEffect(midScale)
                Circle().fill(accent)
                    .frame(width: 104, height: 104)
                Image(systemName: "mic.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 184, height: 184)
    }
}

/// Idle, continuously pulsing capture button. Tap to begin.
struct IdleMicButton: View {
    @Environment(\.appAccent) private var accent
    var systemImage: String
    var caption: String
    var onTap: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.14))
                        .frame(width: 184, height: 184)
                        .scaleEffect(pulse ? 1.12 : 0.92)
                        .opacity(pulse ? 0.45 : 0.9)
                    Circle()
                        .fill(accent.opacity(0.22))
                        .frame(width: 134, height: 134)
                        .scaleEffect(pulse ? 1.06 : 0.96)
                    Circle()
                        .fill(accent)
                        .frame(width: 104, height: 104)
                    Image(systemName: systemImage)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Active listening: mic pulses with the live audio level, transcript streams in.
struct ListeningView: View {
    @Environment(\.appAccent) private var accent
    var audioLevel: Double
    var transcript: String
    var prompt: String
    var subtitle: String?
    var showSkip: Bool = false
    var onDone: () -> Void
    var onSkip: () -> Void = {}

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            ZStack {
                Circle()
                    .fill(accent.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .scaleEffect(1 + audioLevel * 0.9)
                    .animation(.easeOut(duration: 0.12), value: audioLevel)
                Circle()
                    .fill(accent.opacity(0.35))
                    .frame(width: 110, height: 110)
                    .scaleEffect(1 + audioLevel * 0.5)
                    .animation(.easeOut(duration: 0.12), value: audioLevel)
                Image(systemName: "mic.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(accent)
            }
            Text(transcript.isEmpty ? prompt : transcript)
                .font(transcript.isEmpty ? .body : .title3.weight(.medium))
                .foregroundStyle(transcript.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .animation(.default, value: transcript)
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            if showSkip {
                Button("Skip — name it later", action: onSkip)
                    .font(.subheadline)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 24)
    }
}

/// Spinner + status text while parsing / reading a label / estimating a dish.
/// The text always comes from MealCaptureCoordinator.WorkKind — the single
/// operation→string mapping — so different screens can't drift apart.
struct AnalyzingView: View {
    var text: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// A permission / transient-error state with an action button.
struct CaptureProblemView<Action: View>: View {
    var message: String
    var systemImage: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            action()
        }
    }
}

/// Live label scanner with an auto-capture reticle, plus a denied state.
struct ScannerScreen: View {
    @Environment(\.appAccent) private var accent
    var onCapture: (Data) -> Void
    @State private var denied = false

    var body: some View {
        if denied {
            CaptureProblemView(
                message: "MacroLog needs camera access to scan labels. Enable it in Settings.",
                systemImage: "camera.fill"
            ) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ZStack {
                LiveLabelScannerView(onCapture: onCapture, onDenied: { denied = true })
                    .ignoresSafeArea()
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(accent, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                        .frame(maxWidth: 230)
                        .frame(height: 360)
                    Text("Point at the nutrition label — it captures automatically. Tap to grab it now.")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 16)
                    Spacer()
                }
                .padding()
            }
        }
    }
}

/// The inline review: one card per parsed item plus the Save All bar. Nothing
/// is written until every item is confirmed/edited.
struct MealReviewView: View {
    @ObservedObject var coordinator: MealCaptureCoordinator
    var onSaved: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let raw = coordinator.review?.rawText {
                        Text("You said: \u{201C}\(raw)\u{201D}")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !(coordinator.review?.items.isEmpty ?? true) {
                        HStack {
                            Label("Date", systemImage: "calendar")
                                .font(.subheadline)
                            Spacer()
                            DatePicker(
                                "",
                                selection: $coordinator.logDate,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                        }
                    }
                    ForEach(coordinator.review?.items ?? []) { item in
                        ReviewItemCard(item: item, coordinator: coordinator)
                    }
                    if coordinator.review?.items.isEmpty ?? true {
                        ContentUnavailableView(
                            "Nothing left to review",
                            systemImage: "tray",
                            description: Text("All items were removed. Cancel to start over.")
                        )
                    }
                }
                .padding()
            }
            saveBar
        }
    }

    private var saveBar: some View {
        VStack(spacing: 4) {
            if !coordinator.canSaveAll, !(coordinator.review?.items.isEmpty ?? true) {
                Text("Confirm or edit every item to save")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task {
                    await coordinator.saveAll()
                    if coordinator.review == nil { onSaved() }
                }
            } label: {
                Text("Save All").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!coordinator.canSaveAll)
        }
        .padding()
        .background(.bar)
    }
}
