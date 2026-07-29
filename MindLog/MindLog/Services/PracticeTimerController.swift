import Foundation
import SwiftUI
import UIKit

/// Drives a timed practice session (guided breathing or the meditation timer):
/// elapsed-time bookkeeping with pause/resume, a coarse tick for labels and
/// completion, and haptics. The breathing circle itself animates off
/// `TimelineView(.animation)` reading `elapsed` every frame — the published
/// tick only needs to be fast enough for text and phase changes.
@MainActor
final class PracticeTimerController: ObservableObject {
    enum SessionState: Equatable { case running, paused, finished }

    @Published private(set) var state: SessionState = .running
    /// Bumped by the timer so labels/progress re-render between frames.
    @Published private(set) var now = Date()

    let duration: Double
    let pattern: BreathingPattern?

    /// Elapsed seconds from segments completed before the current one.
    private var accumulated: Double = 0
    /// When the current running segment started; nil while paused/finished.
    private var segmentStart: Date?
    private var timer: Timer?
    private var lastStepIndex = -1

    init(duration: Double, pattern: BreathingPattern? = nil) {
        self.duration = duration
        self.pattern = pattern
        segmentStart = Date()
        startTimer()
        // Keep the screen awake for the whole session — a breathing guide
        // that sleeps mid-inhale is worse than none.
        UIApplication.shared.isIdleTimerDisabled = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    var elapsed: Double {
        accumulated + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    var remaining: Double { max(0, duration - elapsed) }
    var progress: Double { duration > 0 ? min(1, elapsed / duration) : 1 }

    /// Whole minutes practiced, for auto-logging — at least 1 once a session
    /// finishes or runs ≥ 30 s, so a completed short breather still counts.
    var minutesForLog: Double {
        let mins = (elapsed / 60).rounded(.down)
        if mins < 1 { return elapsed >= 30 || state == .finished ? 1 : 0 }
        return mins
    }

    func togglePause() {
        switch state {
        case .running:
            accumulated = elapsed
            segmentStart = nil
            state = .paused
            timer?.invalidate()
            timer = nil
        case .paused:
            segmentStart = Date()
            state = .running
            startTimer()
        case .finished:
            break
        }
    }

    /// Ends the session early, keeping the time already practiced.
    func endNow() {
        guard state != .finished else { return }
        accumulated = elapsed
        segmentStart = nil
        finish()
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard state == .running else { return }
        now = Date()
        if let pattern {
            let stepIndex = pattern.position(at: elapsed).stepIndex
            if stepIndex != lastStepIndex {
                lastStepIndex = stepIndex
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
        if elapsed >= duration {
            accumulated = duration
            segmentStart = nil
            finish()
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        state = .finished
        UIApplication.shared.isIdleTimerDisabled = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
