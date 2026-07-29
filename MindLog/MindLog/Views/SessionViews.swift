import SwiftUI
import SwiftData
import UIKit

/// Full-screen guided breathing: a circle that grows and shrinks with the
/// pattern, step labels ("Breathe in… hold…"), soft haptics on each step, and
/// automatic logging when the session ends. Closing with ✕ discards; finishing
/// (or "End session") keeps the minutes.
struct BreathingSessionView: View {
    let pattern: BreathingPattern
    let duration: Double

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent

    @StateObject private var controller: PracticeTimerController
    @State private var logged = false

    init(pattern: BreathingPattern, duration: Double) {
        self.pattern = pattern
        self.duration = duration
        _controller = StateObject(wrappedValue: PracticeTimerController(duration: duration, pattern: pattern))
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                topBar
                Spacer()
                if controller.state == .finished {
                    finishedSummary
                } else {
                    breathingGuide
                }
                Spacer()
                controls
            }
            .padding()
        }
        .onChange(of: controller.state) { _, state in
            if state == .finished { logSession() }
        }
        .onDisappear { controller.shutdown() }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.name).font(.headline)
                Text(remainingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                controller.shutdown()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Close without saving")
        }
    }

    private var breathingGuide: some View {
        VStack(spacing: 36) {
            TimelineView(.animation) { _ in
                let elapsed = controller.elapsed
                let scale = pattern.scale(at: elapsed)
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.10))
                        .frame(width: 280, height: 280)
                    Circle()
                        .fill(accent.opacity(0.22))
                        .frame(width: 280, height: 280)
                        .scaleEffect(scale)
                    Circle()
                        .fill(accent.opacity(0.85))
                        .frame(width: 120, height: 120)
                        .scaleEffect(scale)
                }
            }
            .frame(width: 300, height: 300)

            VStack(spacing: 6) {
                Text(currentStepLabel)
                    .font(.title2.weight(.semibold))
                    .animation(.none, value: currentStepLabel)
                Text(controller.state == .paused ? "Paused" : "Follow the circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Reads `controller.now` so it re-renders on every tick.
    private var currentStepLabel: String {
        _ = controller.now
        return pattern.position(at: controller.elapsed).step.label
    }

    private var remainingText: String {
        _ = controller.now
        let remaining = Int(controller.remaining.rounded())
        return String(format: "%d:%02d left", remaining / 60, remaining % 60)
    }

    private var finishedSummary: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(accent)
            Text("Nice work")
                .font(.title2.weight(.semibold))
            Text("\(Int(controller.minutesForLog)) min of \(pattern.name.lowercased()) logged to today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var controls: some View {
        Group {
            if controller.state == .finished {
                Button {
                    dismiss()
                } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                HStack(spacing: 14) {
                    Button {
                        controller.togglePause()
                    } label: {
                        Label(
                            controller.state == .paused ? "Resume" : "Pause",
                            systemImage: controller.state == .paused ? "play.fill" : "pause.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        controller.endNow()
                    } label: {
                        Text("End session").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    private func logSession() {
        guard !logged else { return }
        let minutes = controller.minutesForLog
        guard minutes > 0 else { return }
        logged = true
        context.insert(ActivityLog(
            activityID: ActivityCatalog.breathwork,
            minutes: minutes,
            note: pattern.name
        ))
    }
}

/// Full-screen meditation timer: a countdown ring, pause/resume, and
/// automatic logging of the minutes actually sat.
struct MeditationTimerView: View {
    let duration: Double

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent

    @StateObject private var controller: PracticeTimerController
    @State private var logged = false

    init(duration: Double) {
        self.duration = duration
        _controller = StateObject(wrappedValue: PracticeTimerController(duration: duration))
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                topBar
                Spacer()
                if controller.state == .finished {
                    finishedSummary
                } else {
                    ring
                }
                Spacer()
                controls
            }
            .padding()
        }
        .onChange(of: controller.state) { _, state in
            if state == .finished { logSession() }
        }
        .onDisappear { controller.shutdown() }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meditation").font(.headline)
                Text("Settle in — the screen stays awake.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                controller.shutdown()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Close without saving")
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: controller.progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text(remainingText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(controller.state == .paused ? "Paused" : "remaining")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 260, height: 260)
    }

    private var remainingText: String {
        _ = controller.now
        let remaining = Int(controller.remaining.rounded())
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private var finishedSummary: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(accent)
            Text("Session complete")
                .font(.title2.weight(.semibold))
            Text("\(Int(controller.minutesForLog)) min of meditation logged to today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var controls: some View {
        Group {
            if controller.state == .finished {
                Button {
                    dismiss()
                } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                HStack(spacing: 14) {
                    Button {
                        controller.togglePause()
                    } label: {
                        Label(
                            controller.state == .paused ? "Resume" : "Pause",
                            systemImage: controller.state == .paused ? "play.fill" : "pause.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        controller.endNow()
                    } label: {
                        Text("End session").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    private func logSession() {
        guard !logged else { return }
        let minutes = controller.minutesForLog
        guard minutes > 0 else { return }
        logged = true
        context.insert(ActivityLog(
            activityID: ActivityCatalog.meditation,
            minutes: minutes
        ))
    }
}
