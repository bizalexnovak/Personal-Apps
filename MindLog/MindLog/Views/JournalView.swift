import SwiftUI
import SwiftData
import UIKit

/// The Journal tab: a voice-first capture surface with the diary timeline
/// beneath it. Tap the pulsing mic and talk — the transcript streams in live,
/// listening auto-stops after a long pause, and the entry lands in a review
/// editor (fix wording, attach a mood) before anything is saved. A keyboard
/// path does the same without speaking. Nothing is written until Save.
struct JournalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appAccent) private var accent
    @Environment(\.appBackground) private var appBackground
    @EnvironmentObject private var hub: AppHub

    @StateObject private var speech = SpeechCaptureController()
    @Query(sort: \JournalEntry.timestamp, order: .reverse) private var entries: [JournalEntry]

    @State private var reviewing = false
    @State private var reviewText = ""
    @State private var reviewMood: Int?
    @State private var reviewSource = EntrySource.voice
    @State private var sentimentHint: String?
    @State private var confirmDiscard = false
    @State private var editingEntry: JournalEntry?
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if reviewing {
                    reviewEditor
                } else {
                    switch speech.state {
                    case .listening, .requestingPermission:
                        ListeningView(
                            audioLevel: speech.audioLevel,
                            transcript: speech.transcript,
                            prompt: "Listening — what's on your mind?",
                            onDone: { speech.finishListening() },
                            onCancel: { speech.cancel() }
                        )
                        .padding(.bottom, AppTabBar.clearance)
                    case .denied(let message):
                        CaptureProblemView(message: message, systemImage: "mic.slash.fill") {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.bottom, AppTabBar.clearance)
                    case .failed(let message):
                        CaptureProblemView(message: message, systemImage: "waveform.slash") {
                            HStack {
                                Button("Not now") { speech.cancel() }
                                    .buttonStyle(.bordered)
                                Button("Try again") {
                                    Task { await speech.restart() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.bottom, AppTabBar.clearance)
                    case .idle, .captured:
                        idleSurface
                    }
                }
            }
            .appBackground(appBackground)
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: speech.state) { _, newState in
            if newState == .captured {
                beginReview(text: speech.transcript, source: EntrySource.voice)
                speech.cancel()
            }
        }
        .onChange(of: hub.pendingJournalAction) { _, action in
            consume(action)
        }
        .onAppear { consume(hub.pendingJournalAction) }
        .sheet(item: $editingEntry) { entry in
            JournalEntryDetailView(entry: entry)
        }
        .confirmationDialog(
            "Discard this entry?", isPresented: $confirmDiscard, titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { resetReview() }
            Button("Keep writing", role: .cancel) {}
        }
    }

    private func consume(_ action: AppHub.JournalAction?) {
        guard let action else { return }
        hub.pendingJournalAction = nil
        guard !reviewing else { return }
        switch action {
        case .voice:
            Task { await speech.start() }
        case .type:
            beginReview(text: "", source: EntrySource.typed)
        }
    }

    // MARK: - Idle: mic + timeline

    private var idleSurface: some View {
        ScrollView {
            VStack(spacing: 10) {
                Button {
                    Task { await speech.start() }
                } label: {
                    MicGraphic(audioLevel: nil)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start a voice entry")

                Text("Tap and say what's on your mind")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    beginReview(text: "", source: EntrySource.typed)
                } label: {
                    Label("Type instead", systemImage: "keyboard")
                        .font(.subheadline)
                }
                .padding(.top, 2)

                timeline
                    .padding(.top, 18)
            }
            .padding()
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            if entries.isEmpty {
                Text("Your entries will appear here. They never leave this phone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                ForEach(groupedByDay, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayLabel(group.day))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        ForEach(group.items) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
        }
    }

    private var groupedByDay: [(day: Date, items: [JournalEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        return groups.keys.sorted(by: >).map { (day: $0, items: groups[$0] ?? []) }
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    private func entryRow(_ entry: JournalEntry) -> some View {
        Button {
            editingEntry = entry
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(entry.moodScore.map(Mood.emoji(for:)) ?? "📝")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    if entry.isCheckIn {
                        Text("Mood check-in — \(Mood.label(for: entry.moodScore ?? 3))")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    } else {
                        Text(entry.snippet)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Text(timeText(entry.timestamp))
                        if entry.source == EntrySource.voice {
                            Image(systemName: "mic.fill").font(.system(size: 9))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button(role: .destructive) {
                context.delete(entry)
            } label: {
                Label("Delete entry", systemImage: "trash")
            }
        }
    }

    // MARK: - Review & save

    private func beginReview(text: String, source: String) {
        reviewText = text
        reviewSource = source
        reviewMood = nil
        sentimentHint = nil
        reviewing = true
        if source == EntrySource.typed {
            // Give the editor a beat to appear before asking for focus.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                editorFocused = true
            }
        }
    }

    private var reviewEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(reviewSource == EntrySource.voice ? "Here's what I heard — edit anything." : "Write freely — this stays on your phone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $reviewText)
                    .focused($editorFocused)
                    .frame(minHeight: 180)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    )

                if let sentimentHint {
                    Label(sentimentHint, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("How do you feel right now?")
                        .font(.subheadline.weight(.medium))
                    MoodPicker(selection: $reviewMood)
                    Text("Optional — but it's what powers your mood trends.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                HStack(spacing: 14) {
                    Button("Discard", role: .destructive) {
                        if reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            resetReview()
                        } else {
                            confirmDiscard = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        saveEntry()
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSave)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .keyboardDismissBar()
        .task(id: reviewText) {
            // Debounced on-device sentiment hint; purely informational. The
            // sleep throws on cancellation — bail out then, otherwise every
            // keystroke's cancelled task would still run the NLTagger pass.
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            let text = reviewText
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 25 else {
                sentimentHint = nil
                return
            }
            if let score = SentimentAnalyzer.score(for: text) {
                sentimentHint = SentimentAnalyzer.hint(for: score)
            } else {
                sentimentHint = nil
            }
        }
    }

    private var canSave: Bool {
        !reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reviewMood != nil
    }

    private func saveEntry() {
        let text = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = JournalEntry(
            text: text,
            source: text.isEmpty ? EntrySource.checkIn : reviewSource,
            moodScore: reviewMood,
            sentimentScore: SentimentAnalyzer.score(for: text)
        )
        context.insert(entry)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        resetReview()
    }

    private func resetReview() {
        reviewing = false
        reviewText = ""
        reviewMood = nil
        sentimentHint = nil
        editorFocused = false
    }
}
