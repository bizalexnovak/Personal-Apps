import SwiftUI
import SwiftData
import UIKit

/// The Log tab: an inline capture surface. Voice by default (a medallion mic you
/// tap to start recording on this same screen — no modal), a camera-app-style
/// switch to Scan (auto-captures a nutrition label), Dish (photograph a meal
/// for an AI estimate) or Barcode, a keyboard button to type, and one-tap
/// "quick add" suggestions for items you log often. Capture, matching, and the
/// review all happen here; logged meals are viewed and edited on the Today tab.
struct MealListView: View {
    @EnvironmentObject private var coordinator: MealCaptureCoordinator
    @EnvironmentObject private var hub: CaptureHub
    @Environment(\.modelContext) private var modelContext
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

    private var isListening: Bool { speech.state == .listening }

    private func refreshSuggestions() {
        suggestions = MealSuggestions.compute(from: meals)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .luxScreen()
                .keyboardDismissBar()
                .animation(.easeInOut(duration: 0.3), value: coordinator.review?.id)
                .toolbar(.hidden, for: .navigationBar)
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
                bottomClearance: OrbNavBar.orbOnlyClearance - 16, // saveBar has 16 of its own
                onCancel: reset
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
                cameraPhase {
                    ScannerScreen(onCapture: { data in
                        Task { await coordinator.beginFromLabel(imageData: data, in: modelContext) }
                    })
                }
            case .dish:
                cameraPhase {
                    DishCameraScreen { data in
                        Task { await coordinator.beginFromDishPhoto(imageData: data, in: modelContext) }
                    }
                }
            case .barcode:
                cameraPhase {
                    BarcodeScannerScreen(
                        notice: coordinator.notice,
                        onScan: { barcode in
                            coordinator.notice = nil
                            Task { await coordinator.beginFromBarcode(barcode, in: modelContext) }
                        }
                    )
                }
            }
        }
    }

    /// The three camera modes share a shell: header, live feed, mode switcher.
    /// The camera only runs while the Log tab is actually showing.
    private func cameraPhase<Feed: View>(@ViewBuilder feed: () -> Feed) -> some View {
        ZStack(alignment: .bottom) {
            if hub.selectedTab == AppTab.log {
                feed()
            } else {
                Lux.cameraGround
            }
            VStack(spacing: 0) {
                header
                Spacer()
                modeSwitcher.padding(.bottom, OrbNavBar.orbOnlyClearance)
            }
        }
    }

    @ViewBuilder
    private var voicePhase: some View {
        switch speech.state {
        case .listening:
            voiceLayout(listening: true)
        case .requestingPermission:
            AnalyzingView(text: "Getting the microphone ready…")
        case .denied(let message):
            CaptureProblemView(message: message, systemImage: "mic.slash.fill") {
                Button("OPEN SETTINGS") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(GhostCapsule(gold: true))
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

    /// The medallion is pinned to a fixed position (via absolute placement) so
    /// it does NOT move between idle and listening — only the halos, the text,
    /// and the controls at the bottom change. Tapping it starts recording;
    /// while listening the chips and switcher give way to Done.
    private func voiceLayout(listening: Bool, note: String? = nil) -> some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let micY = geo.size.height * 0.30

            VStack(spacing: 0) {
                header
                Spacer()
            }

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
                .accessibilityLabel(listening ? "Stop listening" : "Start listening")

            Text(micText(listening: listening, note: note))
                .font(Lux.serifItalic(listening && !speech.transcript.isEmpty ? 22 : 17))
                .foregroundStyle(Lux.cream.opacity(listening && !speech.transcript.isEmpty ? 1 : 0.55))
                .multilineTextAlignment(.center)
                // Clamped: transient layout passes can report a width under
                // 40 pt, and a negative maxWidth trips SwiftUI's "Invalid
                // frame dimension" warning.
                .frame(maxWidth: max(0, geo.size.width - 2 * Lux.hPad))
                .position(x: midX, y: micY + MicGraphic.captionOffset + 8)
                .animation(.default, value: speech.transcript)

            // Bottom controls, anchored independently of the medallion. While
            // listening the chips and switcher give way to a single Done.
            VStack(spacing: 0) {
                Spacer()
                if listening {
                    Button("DONE") { speech.finishListening() }
                        .buttonStyle(GoldCapsule())
                        .frame(maxWidth: 220)
                        .padding(.bottom, OrbNavBar.orbOnlyClearance)
                } else {
                    if !suggestions.isEmpty {
                        suggestionsStrip
                            .padding(.bottom, 46)
                    }
                    modeSwitcher
                        .padding(.bottom, OrbNavBar.orbOnlyClearance)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func micText(listening: Bool, note: String?) -> String {
        if listening {
            return speech.transcript.isEmpty
                ? "Listening…"
                : "\u{201C}\(speech.transcript)\u{201D}"
        }
        return note ?? "Tap and describe what you consumed."
    }

    private var nameStep: some View {
        ListeningView(
            audioLevel: speech.audioLevel,
            transcript: speech.transcript,
            prompt: "Listening… what's this item called?",
            subtitle: "Label scanned. Say the name of this food.",
            showSkip: true,
            bottomClearance: OrbNavBar.orbOnlyClearance,
            onDone: { speech.finishListening() },
            onSkip: {
                speech.cancel()
                coordinator.finishLabel(name: "", in: modelContext)
            }
        )
    }

    // MARK: - Header

    /// Weekday and a keyboard escape hatch while idle; cancel and a listening
    /// indicator once the mic is live.
    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                if isListening || coordinator.pendingLabel != nil {
                    Button("CANCEL") { reset() }
                        .font(Lux.smallcaps(10))
                        .tracking(3)
                        .foregroundStyle(Lux.cream.opacity(0.6))
                    Spacer()
                    Text("LISTENING")
                        .font(Lux.smallcaps(10))
                        .tracking(3)
                        .foregroundStyle(Lux.gold)
                } else {
                    Text(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(Lux.smallcaps(10))
                        .tracking(3)
                        .foregroundStyle(Lux.goldLabel)
                    Spacer()
                    Button { showTypeSheet = true } label: {
                        Image(systemName: "keyboard")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Lux.cream)
                    }
                    .accessibilityLabel("Type instead")
                }
            }
            .padding(.bottom, 8)

            LuxTitle(text: "LOG")

            Text("Voice, label, dish, or barcode.")
                .font(Lux.serifItalic(15))
                .foregroundStyle(Lux.cream.opacity(0.55))
                .padding(.top, 6)
        }
        .padding(.horizontal, Lux.hPad)
        .padding(.top, 64)
    }

    // MARK: - Quick-add suggestions

    private var suggestionsStrip: some View {
        VStack(spacing: 10) {
            Text("QUICK ADD")
                .font(Lux.smallcaps(9))
                .tracking(2.5)
                .foregroundStyle(Lux.goldLabel)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button { quickLog(suggestion) } label: {
                            VStack(spacing: 2) {
                                Text(suggestion.name)
                                    .font(Lux.serif(15))
                                    .foregroundStyle(Lux.cream)
                                    .lineLimit(1)
                                Text("\(quantityText(suggestion)) \(suggestion.unit.uppercased()) · \(Int(suggestion.calories.rounded())) KCAL")
                                    .font(Lux.smallcaps(7))
                                    .tracking(1.5)
                                    .foregroundStyle(Lux.goldLabel)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().stroke(Lux.controlBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Lux.hPad)
            }
        }
    }

    private func quantityText(_ s: MealSuggestion) -> String {
        s.quantity == s.quantity.rounded() ? "\(Int(s.quantity))" : s.quantity.formatted()
    }

    @ViewBuilder
    private var quickAddToast: some View {
        if let lastQuickAdd {
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                Text("ADDED \(lastQuickAdd.uppercased())")
                    .font(Lux.smallcaps(9))
                    .tracking(2)
            }
            .foregroundStyle(Lux.ground)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Capsule().fill(Lux.goldFill))
            .luxFloating()
            .padding(.bottom, OrbNavBar.orbOnlyClearance)
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

    // MARK: - Mode switcher

    private var modeSwitcher: some View {
        LuxSwitcher(
            options: LogCaptureMode.allCases.map { ($0, $0.title.uppercased()) },
            selection: Binding(
                get: { mode },
                set: { option in
                    mode = option
                    hub.logMode = option
                    if option != .voice { speech.cancel() }
                }
            ),
            spacing: 20,
            size: 10
        )
    }

    // MARK: - Typed entry

    private var typeSheet: some View {
        LuxSheet {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button("CANCEL") { typedText = ""; showTypeSheet = false }
                        .font(Lux.smallcaps(9))
                        .tracking(2)
                        .foregroundStyle(Lux.cream.opacity(0.6))
                    Spacer()
                    Button("LOG") { submitTyped() }
                        .font(Lux.smallcaps(9))
                        .tracking(2)
                        .foregroundStyle(canSubmitTyped ? Lux.gold : Lux.cream.opacity(0.35))
                        .disabled(!canSubmitTyped)
                }
                .padding(.top, 18)

                Text("BY HAND")
                    .font(Lux.title(20))
                    .tracking(3)
                    .engravedFill()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)

                LuxUnderlinedField(
                    placeholder: "Two eggs and a slice of toast…",
                    text: $typedText,
                    autocapitalization: .sentences
                )
                .padding(.top, 26)

                LuxNote("Describe what you consumed — plain English is enough.")
                    .padding(.top, 12)

                Spacer()
            }
            .padding(.horizontal, Lux.hPad)
        }
        .presentationDetents([.medium])
    }

    private var canSubmitTyped: Bool {
        !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
