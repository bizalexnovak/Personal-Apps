import SwiftUI
import UIKit

/// Full-screen voice capture: starts listening on appear, shows a pulsing mic
/// and the live transcript, auto-stops on silence (or Done). The finalized
/// transcript hands off straight to the parsing/lookup pipeline — review
/// happens on the Match Review Screen, not here.
struct VoiceLogView: View {
    @EnvironmentObject private var coordinator: MealCaptureCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechCaptureController()

    var body: some View {
        NavigationStack {
            Group {
                switch speech.state {
                case .idle, .requestingPermission:
                    ProgressView("Getting the microphone ready…")

                case .listening:
                    listeningView

                case .captured:
                    // Momentary — the onChange handler below dismisses and
                    // starts the pipeline; the loading HUD lives in ContentView.
                    ProgressView("Got it — analyzing…")

                case .denied(let message):
                    problemView(message: message, systemImage: "mic.slash.fill") {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                case .failed(let message):
                    problemView(message: message, systemImage: "waveform.slash") {
                        Button("Try again") {
                            Task { await speech.restart() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Log a Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        speech.cancel()
                        dismiss()
                    }
                }
            }
        }
        .task {
            await speech.start()
        }
        .onChange(of: speech.state) { _, newState in
            guard case .captured = newState else { return }
            let text = speech.transcript
            dismiss()
            Task { await coordinator.begin(text: text, in: modelContext) }
        }
        .onDisappear {
            speech.cancel()
        }
    }

    // MARK: - Listening

    private var listeningView: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.orange.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .scaleEffect(1 + speech.audioLevel * 0.9)
                    .animation(.easeOut(duration: 0.12), value: speech.audioLevel)
                Circle()
                    .fill(.orange.opacity(0.35))
                    .frame(width: 110, height: 110)
                    .scaleEffect(1 + speech.audioLevel * 0.5)
                    .animation(.easeOut(duration: 0.12), value: speech.audioLevel)
                Image(systemName: "mic.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
            }

            Text(speech.transcript.isEmpty ? "Listening… describe what you ate" : speech.transcript)
                .font(speech.transcript.isEmpty ? .body : .title3.weight(.medium))
                .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .animation(.default, value: speech.transcript)

            Spacer()

            Button("Done") {
                speech.finishListening()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Problems

    private func problemView(message: String, systemImage: String, @ViewBuilder action: () -> some View) -> some View {
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
