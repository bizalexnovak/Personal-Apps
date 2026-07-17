import SwiftUI
import SwiftData
import UIKit

/// The Siri / deep-link capture screen, presented modally when the app opens
/// straight onto capture. Starts in voice, scan, or text mode; once parsing +
/// matching finish, the SAME view transitions in place to the review cards.
/// (In-app capture is hosted inline on the Log tab, not here.)
struct CaptureView: View {
    let mode: CaptureMode

    @EnvironmentObject private var coordinator: MealCaptureCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechCaptureController()

    @State private var started = false

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.review != nil {
                    MealReviewView(coordinator: coordinator, onSaved: { dismiss() })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    captureContent
                }
            }
            .animation(.easeInOut(duration: 0.3), value: coordinator.review?.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .keyboardDismissBar()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        speech.cancel()
                        coordinator.cancelReview()
                        dismiss()
                    }
                }
            }
        }
        .task {
            guard !started else { return }
            started = true
            await start()
        }
        .onChange(of: speech.state) { _, newState in
            guard case .captured = newState else { return }
            let text = speech.transcript
            if coordinator.pendingLabel != nil {
                coordinator.finishLabel(name: text, in: modelContext)
            } else {
                Task { await coordinator.begin(text: text, in: modelContext) }
            }
        }
        // A scanned label has macros but no name — kick off voice capture to ask.
        .onChange(of: isNamingLabel) { _, naming in
            if naming { Task { await speech.restart() } }
        }
        .onDisappear { speech.cancel() }
    }

    private var isNamingLabel: Bool { coordinator.pendingLabel != nil }

    private var navigationTitle: String {
        if coordinator.review != nil { return "Review Meal" }
        if isNamingLabel { return "Name the Item" }
        return "Log a Meal"
    }

    // MARK: - Start

    private func start() async {
        switch mode {
        case .voice:
            await speech.start()
        case .text(let text):
            await coordinator.begin(text: text, in: modelContext)
        case .scan:
            break // ScannerScreen drives itself
        }
    }

    // MARK: - Capture phase (pre-review)

    @ViewBuilder
    private var captureContent: some View {
        if coordinator.isWorking {
            AnalyzingView(text: coordinator.workingText)
        } else if isNamingLabel {
            nameStep
        } else {
            switch mode {
            case .voice: voicePhase
            case .scan:
                ScannerScreen(onCapture: { data in
                    Task { await coordinator.beginFromLabel(imageData: data, in: modelContext) }
                })
            case .text:
                AnalyzingView(text: MealCaptureCoordinator.WorkKind.parsingText.text)
            }
        }
    }

    private var nameStep: some View {
        listening(
            prompt: "Listening… what's this item called?",
            subtitle: "Label scanned. Say the name of this food.",
            showSkip: true
        )
    }

    @ViewBuilder
    private var voicePhase: some View {
        switch speech.state {
        case .idle, .requestingPermission:
            ProgressView("Getting the microphone ready…")
        case .listening:
            listening(prompt: "Listening… describe what you consumed", subtitle: nil, showSkip: false)
        case .captured:
            AnalyzingView(text: MealCaptureCoordinator.WorkKind.parsingText.text)
        case .denied(let message):
            CaptureProblemView(message: message, systemImage: "mic.slash.fill") {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .failed(let message):
            CaptureProblemView(message: message, systemImage: "waveform.slash") {
                Button("Try again") { Task { await speech.restart() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func listening(prompt: String, subtitle: String?, showSkip: Bool) -> some View {
        ListeningView(
            audioLevel: speech.audioLevel,
            transcript: speech.transcript,
            prompt: prompt,
            subtitle: subtitle,
            showSkip: showSkip,
            onDone: { speech.finishListening() },
            onSkip: {
                speech.cancel()
                coordinator.finishLabel(name: "", in: modelContext)
            }
        )
    }
}
