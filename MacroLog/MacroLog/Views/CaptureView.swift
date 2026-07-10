import SwiftUI
import SwiftData
import UIKit

/// One screen for the whole capture→review flow. Starts in voice, scan, or
/// text mode; once parsing + matching finish, the SAME view transitions in
/// place to show the review cards (the transcript collapses to a reference
/// line). The user never navigates to a separate review screen.
struct CaptureView: View {
    let mode: CaptureMode

    @EnvironmentObject private var coordinator: MealCaptureCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechCaptureController()

    @State private var showCamera = false
    @State private var started = false

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.review != nil {
                    reviewContent
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    captureContent
                }
            }
            .animation(.easeInOut(duration: 0.3), value: coordinator.review?.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .safeAreaInset(edge: .bottom) {
                if coordinator.review != nil {
                    saveBar
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
        // A scanned label has macros but no name — kick off voice capture to
        // ask the user what it is.
        .onChange(of: isNamingLabel) { _, naming in
            if naming { Task { await speech.restart() } }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                handleScanned(image)
            }
            .ignoresSafeArea()
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
            showCamera = true
        }
    }

    private func handleScanned(_ image: UIImage?) {
        guard let image, let data = image.jpegData(compressionQuality: 0.7) else {
            dismiss() // user cancelled the camera
            return
        }
        Task { await coordinator.beginFromLabel(imageData: data, in: modelContext) }
    }

    // MARK: - Capture phase (pre-review)

    @ViewBuilder
    private var captureContent: some View {
        if coordinator.isWorking {
            analyzingView
        } else if isNamingLabel {
            voicePhase // ask for the scanned item's name by voice
        } else {
            switch mode {
            case .voice: voicePhase
            case .scan: scanPhase
            case .text: analyzingView
            }
        }
    }

    private var analyzingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(mode == .scan ? "Reading the label…" : "Analyzing your meal…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var scanPhase: some View {
        // Camera is presented as a cover; this is the backdrop before/after.
        Color.clear
    }

    @ViewBuilder
    private var voicePhase: some View {
        switch speech.state {
        case .idle, .requestingPermission:
            ProgressView("Getting the microphone ready…")
        case .listening:
            listeningView
        case .captured:
            analyzingView
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

    private var listeningPrompt: String {
        isNamingLabel
            ? "Listening… what's this item called?"
            : "Listening… describe what you ate"
    }

    private var listeningView: some View {
        VStack(spacing: 32) {
            Spacer()
            if isNamingLabel {
                Text("Label scanned. Say the name of this food.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
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
            Text(speech.transcript.isEmpty ? listeningPrompt : speech.transcript)
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
            if isNamingLabel {
                Button("Skip — name it later") {
                    speech.cancel()
                    coordinator.finishLabel(name: "", in: modelContext)
                }
                .font(.subheadline)
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 24)
    }

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

    // MARK: - Review phase (inline)

    private var reviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let raw = coordinator.review?.rawText {
                    Text("You said: \u{201C}\(raw)\u{201D}")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(coordinator.review?.items ?? []) { item in
                    ReviewItemCard(item: item, coordinator: coordinator)
                }
                if (coordinator.review?.items.isEmpty ?? true) {
                    ContentUnavailableView(
                        "Nothing left to review",
                        systemImage: "tray",
                        description: Text("All items were removed. Cancel to start over.")
                    )
                }
            }
            .padding()
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
                    if coordinator.review == nil { dismiss() }
                }
            } label: {
                Text("Save All")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!coordinator.canSaveAll)
        }
        .padding()
        .background(.bar)
    }
}
