import SwiftUI
import SwiftData
import UIKit

/// The Log tab: an inline capture surface. Voice by default (a pulsing mic you
/// tap to start recording on this same screen — no modal), a camera-app-style
/// switch to Scan (auto-captures a nutrition label) or Dish (photograph a meal
/// for an AI estimate), a keyboard button to type, and one-tap "quick add"
/// suggestions for items you log often. Capture, matching, and the review all
/// happen here; logged meals are viewed and edited on the Today tab.
struct MealListView: View {
    @EnvironmentObject private var coordinator: MealCaptureCoordinator
    @EnvironmentObject private var hub: CaptureHub
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackground) private var appBackground
    @StateObject private var speech = SpeechCaptureController()
    @Query(sort: \Meal.timestamp, order: .reverse) private var meals: [Meal]

    @State private var mode: LogCaptureMode = .voice
    @State private var showTypeSheet = false
    @State private var typedText = ""
    @State private var showDishCamera = false
    @State private var lastQuickAdd: String?

    private var suggestions: [MealSuggestion] { MealSuggestions.compute(from: meals) }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackground(appBackground)
                .animation(.easeInOut(duration: 0.3), value: coordinator.review?.id)
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .overlay(alignment: .bottom) { quickAddToast }
                .sheet(isPresented: $showTypeSheet) { typeSheet }
                .fullScreenCover(isPresented: $showDishCamera) {
                    CameraPicker { image in
                        showDishCamera = false
                        handleDishImage(image)
                    }
                    .ignoresSafeArea()
                }
        }
        .onAppear { mode = hub.logMode }
        .onChange(of: hub.logMode) { _, newMode in
            mode = newMode
            if newMode != .voice { speech.cancel() }
        }
        .onChange(of: hub.autoStartVoice) { _, start in
            if start {
                hub.autoStartVoice = false
                mode = .voice
                Task { await speech.restart() }
            }
        }
        .onChange(of: hub.openType) { _, open in
            if open {
                hub.openType = false
                showTypeSheet = true
            }
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
        // After a label scan, ask for the item's name by voice.
        .onChange(of: coordinator.pendingLabel != nil) { _, naming in
            if naming { Task { await speech.restart() } }
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        if coordinator.review != nil {
            MealReviewView(coordinator: coordinator, onSaved: reset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if coordinator.isWorking {
            AnalyzingView(text: analyzingText)
        } else if coordinator.pendingLabel != nil {
            nameStep
        } else {
            switch mode {
            case .voice: voicePhase
            case .scan:
                ZStack(alignment: .bottom) {
                    ScannerScreen(onCapture: { data in
                        Task { await coordinator.beginFromLabel(imageData: data, in: modelContext) }
                    })
                    modeSwitcher.padding(.bottom, 28)
                }
            case .dish:
                dishPhase
            }
        }
    }

    private var analyzingText: String {
        switch mode {
        case .dish: return "Estimating from your photo…"
        case .scan where coordinator.pendingLabel == nil: return "Reading the label…"
        default: return "Analyzing your meal…"
        }
    }

    @ViewBuilder
    private var voicePhase: some View {
        switch speech.state {
        case .listening:
            ListeningView(
                audioLevel: speech.audioLevel,
                transcript: speech.transcript,
                prompt: "Listening… describe what you ate",
                subtitle: nil,
                onDone: { speech.finishListening() }
            )
        case .requestingPermission:
            ProgressView("Getting the microphone ready…")
        case .denied(let message):
            CaptureProblemView(message: message, systemImage: "mic.slash.fill") {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .captured:
            AnalyzingView(text: "Analyzing your meal…")
        case .failed(let message):
            idleVoice(note: message)
        case .idle:
            idleVoice(note: nil)
        }
    }

    /// Idle voice: a pulsing mic to tap, quick-add suggestions, and the switcher.
    private func idleVoice(note: String?) -> some View {
        VStack(spacing: 22) {
            Spacer()
            IdleMicButton(
                systemImage: "mic.fill",
                caption: note ?? "Tap and describe what you ate."
            ) {
                Task { await speech.restart() }
            }
            if !suggestions.isEmpty { suggestionsStrip }
            Spacer()
            modeSwitcher.padding(.bottom, 28)
        }
    }

    private var dishPhase: some View {
        VStack(spacing: 22) {
            Spacer()
            IdleMicButton(
                systemImage: "camera.fill",
                caption: "Take a photo of your dish for an AI nutrition estimate."
            ) {
                showDishCamera = true
            }
            Spacer()
            modeSwitcher.padding(.bottom, 28)
        }
    }

    private var nameStep: some View {
        ListeningView(
            audioLevel: speech.audioLevel,
            transcript: speech.transcript,
            prompt: "Listening… what's this item called?",
            subtitle: "Label scanned. Say the name of this food.",
            showSkip: true,
            onDone: { speech.finishListening() },
            onSkip: {
                speech.cancel()
                coordinator.finishLabel(name: "", in: modelContext)
            }
        )
    }

    // MARK: - Quick-add suggestions

    private var suggestionsStrip: some View {
        VStack(spacing: 6) {
            Text("Quick add")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button { quickLog(suggestion) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text("\(quantityText(suggestion)) \(suggestion.unit) · \(Int(suggestion.calories.rounded())) kcal")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(.quaternary.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func quantityText(_ s: MealSuggestion) -> String {
        s.quantity == s.quantity.rounded() ? "\(Int(s.quantity))" : s.quantity.formatted()
    }

    @ViewBuilder
    private var quickAddToast: some View {
        if let lastQuickAdd {
            Label("Added \(lastQuickAdd)", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func quickLog(_ s: MealSuggestion) {
        let item = FoodItem(
            name: s.name, quantity: s.quantity, unit: s.unit,
            calories: s.calories, protein: s.protein, carbs: s.carbs, fat: s.fat,
            matchConfidence: MatchConfidence.high
        )
        item.micros = s.micros
        let meal = Meal(rawText: s.name, items: [item])
        modelContext.insert(meal)
        try? modelContext.save()
        withAnimation { lastQuickAdd = s.label }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { lastQuickAdd = nil }
        }
    }

    // MARK: - Mode switcher (camera-app style)

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(LogCaptureMode.allCases) { option in
                switchButton(option)
            }
        }
        .padding(4)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    private func switchButton(_ option: LogCaptureMode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { mode = option }
            hub.logMode = option
            if option != .voice { speech.cancel() }
        } label: {
            Text(option.title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(mode == option ? Color.accentColor : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(mode == option ? Color.accentColor.opacity(0.15) : .clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chrome

    private var navigationTitle: String {
        if coordinator.review != nil { return "Review Meal" }
        if coordinator.pendingLabel != nil { return "Name the Item" }
        return "Log"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if coordinator.review != nil || speech.state == .listening || coordinator.pendingLabel != nil {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { reset() }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showTypeSheet = true } label: { Image(systemName: "keyboard") }
                    .accessibilityLabel("Type instead")
            }
        }
    }

    private var typeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Describe what you ate…", text: $typedText, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("Example: \u{201C}two eggs, a slice of toast, and a coffee with milk.\u{201D}")
                }
            }
            .navigationTitle("Type a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { typedText = ""; showTypeSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { submitTyped() }
                        .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func submitTyped() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedText = ""
        showTypeSheet = false
        Task { await coordinator.begin(text: text, in: modelContext) }
    }

    private func handleDishImage(_ image: UIImage?) {
        guard let image, let data = image.jpegData(compressionQuality: 0.7) else { return }
        Task { await coordinator.beginFromDishPhoto(imageData: data, in: modelContext) }
    }

    private func reset() {
        speech.cancel()
        coordinator.cancelReview()
    }
}
