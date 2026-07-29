import SwiftUI
import UIKit

/// Shared building blocks used across tabs.

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
            let pulse = (sin(t * 2 * .pi / 3.0) + 1) / 2 // 0…1 over ~3 s — a calm cadence
            let level = CGFloat(audioLevel ?? 0)
            let outerScale = 0.94 + 0.12 * pulse + level * 0.5
            let midScale = 0.97 + 0.06 * pulse + level * 0.3

            ZStack {
                Circle().fill(accent.opacity(0.15))
                    .frame(width: 172, height: 172)
                    .scaleEffect(outerScale)
                Circle().fill(accent.opacity(0.22))
                    .frame(width: 126, height: 126)
                    .scaleEffect(midScale)
                Circle().fill(accent)
                    .frame(width: 98, height: 98)
                Image(systemName: "mic.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 176, height: 176)
    }
}

/// Active listening: mic pulses with the live audio level, transcript streams in.
struct ListeningView: View {
    @Environment(\.appAccent) private var accent
    var audioLevel: Double
    var transcript: String
    var prompt: String
    var onDone: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            ZStack {
                Circle()
                    .fill(accent.opacity(0.2))
                    .frame(width: 132, height: 132)
                    .scaleEffect(1 + audioLevel * 0.9)
                    .animation(.easeOut(duration: 0.12), value: audioLevel)
                Circle()
                    .fill(accent.opacity(0.35))
                    .frame(width: 104, height: 104)
                    .scaleEffect(1 + audioLevel * 0.5)
                    .animation(.easeOut(duration: 0.12), value: audioLevel)
                Image(systemName: "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(accent)
            }
            ScrollView {
                Text(transcript.isEmpty ? prompt : transcript)
                    .font(transcript.isEmpty ? .body : .title3.weight(.medium))
                    .foregroundStyle(transcript.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .animation(.default, value: transcript)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 180)
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Text("Take your time — pauses are fine.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
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

/// The five-emoji mood row. `selection` toggles off when the same mood is
/// tapped again (so an accidental tap is undoable in place).
struct MoodPicker: View {
    @Binding var selection: Int?
    var size: CGFloat = 34

    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { score in
                Button {
                    selection = (selection == score) ? nil : score
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(Mood.emoji(for: score))
                        .font(.system(size: size))
                        .opacity(selection == nil || selection == score ? 1 : 0.35)
                        .scaleEffect(selection == score ? 1.15 : 1)
                        .padding(6)
                        .background(
                            Circle().fill(selection == score ? accent.opacity(0.18) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Mood.label(for: score))
                .accessibilityAddTraits(selection == score ? .isSelected : [])
            }
        }
        .animation(.spring(duration: 0.25), value: selection)
    }
}

/// Circular progress ring used for the day's practice score.
struct ScoreRing: View {
    var score: Double
    var goal: Double
    var color: Color
    var lineWidth: CGFloat = 12

    private var progress: Double { goal > 0 ? min(1, score / goal) : 0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            VStack(spacing: 0) {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("of \(Int(goal.rounded()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Standard card backdrop for the dashboard sections.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// Time-only text for entry/log rows ("3:42 PM").
func timeText(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}
