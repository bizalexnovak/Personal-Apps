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
    @State private var lastQuickAdd: String?
    /// Cached quick-add chips. Computing them scans the whole history (with a
    /// JSON decode per unique item), so it runs only when the data changes or
    /// the Log tab is revisited — not on every body evaluation.
    @State private var suggestions: [MealSuggestion] = []

    private func refreshSuggestions() {
        suggestions = MealSuggestions.compute(from: meals)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackground(appBackground)
                .keyboardDismissBar()
                .animation(.easeInOut(duration: 0.3), value: coordinator.review?.id)
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .overlay(alignment: .bottom) { quickAddToast }
                .sheet(isPresented: $showTypeSheet) { typeSheet }
        }
        // Consume any queued action on appear (covers a cold launch from Siri,
        // where the flag is already set before this view exists).
        .onAppear {
            mode = hub.logMode
            refreshSuggestions()
            consumeAutoStartVoice()
            consumeOpenType()
        }
        // Recompute only while this tab is visible — changes made elsewhere
        // (deletes on Today, item-level edits, which don't even fire the meals
        // onChange because @Model equality is by identity) are all picked up
        // by the unconditional refresh when the user switches back to Log.
        .onChange(of: meals) { _, _ in
            if hub.selectedTab == AppTab.log { refreshSuggestions() }
        }
        .onChange(of: hub.selectedTab) { _, tab in
            if tab == AppTab.log { refreshSuggestions() }
        }
        .onChange(of: hub.logMode) { _, newMode in
            mode = newMode
            if newMode != .voice { speech.cancel() }
        }
        .onChange(of: hub.autoStartVoice) { _, _ in consumeAutoStartVoice() }
        .onChange(of: hub.openType) { _, _ in consumeOpenType() }
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
            MealReviewView(
                coordinator: coordinator, onSaved: reset,
                bottomClearance: AppTabBar.clearance - 16 // saveBar has 16 of its own
            )
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if coordinator.isWorking {
            AnalyzingView(text: coordinator.workingText)
        } else if coordinator.pendingLabel != nil {
            nameStep
        } else {
            switch mode {
            case .voice: voicePhase
            case .scan:
                ZStack(alignment: .bottom) {
                    // Only run the camera while the Log tab is actually showing.
                    if hub.selectedTab == AppTab.log {
                        ScannerScreen(onCapture: { data in
                            Task { await coordinator.beginFromLabel(imageData: data, in: modelContext) }
                        })
                    } else {
                        Color.clear
                    }
                    modeSwitcher.padding(.bottom, AppTabBar.clearance)
                }
            case .dish:
                dishPhase
            case .barcode:
                barcodePhase
            }
        }
    }

    @ViewBuilder
    private var voicePhase: some View {
        switch speech.state {
        case .listening:
            voiceLayout(listening: true)
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
            // Parsing is about to start but hasn't set workKind yet — a voice
            // capture always feeds the text parser, so use that kind directly.
            AnalyzingView(text: MealCaptureCoordinator.WorkKind.parsingText.text)
        case .failed(let message):
            voiceLayout(listening: false, note: message)
        case .idle:
            voiceLayout(listening: false, note: nil)
        }
    }

    /// The mic is pinned to a fixed position (via absolute placement) so it does
    /// NOT move between idle and listening — only the text and the controls at
    /// the bottom change. Tapping the mic (idle) starts recording; while
    /// listening the suggestions/switcher give way to Done, and it keeps pulsing.
    private func voiceLayout(listening: Bool, note: String? = nil) -> some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let micY = geo.size.height * 0.40

            // The mic is a toggle: tap to start listening, tap again to stop.
            MicGraphic(audioLevel: listening ? speech.audioLevel : nil)
                .contentShape(Circle())
                .onTapGesture {
                    if listening {
                        speech.finishListening()
                    } else {
                        Task { await speech.restart() }
                    }
                }
                .position(x: midX, y: micY)

            Text(micText(listening: listening, note: note))
                .font(listening && !speech.transcript.isEmpty ? .title3.weight(.medium) : .body)
                .foregroundStyle(listening && !speech.transcript.isEmpty ? .primary : .secondary)
                .multilineTextAlignment(.center)
                // Clamped: transient layout passes can report a width under
                // 40 pt, and a negative maxWidth trips SwiftUI's "Invalid
                // frame dimension" warning.
                .frame(maxWidth: max(0, geo.size.width - 40))
                .position(x: midX, y: micY + 128)
                .animation(.default, value: speech.transcript)

            // Bottom controls, anchored to the bottom independently of the mic.
            // While listening they simply disappear — tapping the mic again stops.
            // Only the switcher carries the tab-bar clearance (a Group would
            // stamp it onto every child); the 64 pt gap sits the quick-add
            // strip roughly midway between the mic caption and the switcher.
            if !listening {
                VStack(spacing: 0) {
                    Spacer()
                    if !suggestions.isEmpty {
                        suggestionsStrip
                            .padding(.bottom, 64)
                    }
                    modeSwitcher
                        .padding(.bottom, AppTabBar.clearance)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func micText(listening: Bool, note: String?) -> String {
        if listening {
            return speech.transcript.isEmpty ? "Listening… describe what you consumed" : speech.transcript
        }
        return note ?? "Tap and describe what you consumed."
    }

    private var dishPhase: some View {
        ZStack(alignment: .bottom) {
            // Live camera with a manual shutter (framing a dish is the user's
            // call, unlike labels which auto-capture). Only run the camera
            // while the Log tab is actually showing.
            if hub.selectedTab == AppTab.log {
                DishCameraScreen { data in
                    Task { await coordinator.beginFromDishPhoto(imageData: data, in: modelContext) }
                }
            } else {
                Color.clear
            }
            modeSwitcher.padding(.bottom, AppTabBar.clearance)
        }
    }

    private var barcodePhase: some View {
        ZStack(alignment: .bottom) {
            if hub.selectedTab == AppTab.log {
                BarcodeScannerScreen(
                    notice: coordinator.notice,
                    onScan: { barcode in
                        coordinator.notice = nil
                        Task { await coordinator.beginFromBarcode(barcode, in: modelContext) }
                    }
                )
            } else {
                Color.clear
            }
            modeSwitcher.padding(.bottom, AppTabBar.clearance)
        }
    }

    private var nameStep: some View {
        ListeningView(
            audioLevel: speech.audioLevel,
            transcript: speech.transcript,
            prompt: "Listening… what's this item called?",
            subtitle: "Label scanned. Say the name of this food.",
            showSkip: true,
            bottomClearance: AppTabBar.clearance,
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
                    TextField("Describe what you consumed…", text: $typedText, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("Example: \u{201C}two eggs, a slice of toast, and a coffee with milk.\u{201D}")
                }
            }
            .keyboardDismissBar()
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

    private func consumeAutoStartVoice() {
        guard hub.autoStartVoice else { return }
        hub.autoStartVoice = false
        mode = .voice
        Task { await speech.restart() }
    }

    private func consumeOpenType() {
        guard hub.openType else { return }
        hub.openType = false
        showTypeSheet = true
    }

    private func submitTyped() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedText = ""
        showTypeSheet = false
        Task { await coordinator.begin(text: text, in: modelContext) }
    }

    private func reset() {
        speech.cancel()
        coordinator.cancelReview()
    }
}
