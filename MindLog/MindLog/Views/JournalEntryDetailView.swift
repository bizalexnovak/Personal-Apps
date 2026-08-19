import SwiftUI
import SwiftData

/// Read/edit sheet for one journal entry: fix the text, change the mood,
/// adjust when it happened, or delete it. Sentiment is recomputed on save so
/// the trends stay honest after edits.
struct JournalEntryDetailView: View {
    @Bindable var entry: JournalEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var mood: Int?
    @State private var timestamp: Date = .now
    @State private var confirmDelete = false
    @State private var emotionWords: [String] = []
    @State private var contextTags: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.quaternary, lineWidth: 0.5)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mood")
                            .font(.subheadline.weight(.medium))
                        MoodPicker(selection: $mood)
                    }

                    DatePicker(
                        "When",
                        selection: $timestamp,
                        in: EntryEditing.earliestAllowed()...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(.subheadline)

                    // Same optional, skippable layer as the check-in detail
                    // step — any entry can gain or lose words/tags later.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Feeling words")
                            .font(.subheadline.weight(.medium))
                        FlowLayout(spacing: 8) {
                            ForEach(EmotionVocabulary.words(for: mood ?? 3), id: \.self) { word in
                                SelectableChip(label: word, isOn: emotionWords.contains(word)) {
                                    emotionWords = toggling(word, in: emotionWords)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Context")
                            .font(.subheadline.weight(.medium))
                        ForEach(ContextTagCatalog.groups, id: \.title) { group in
                            FlowLayout(spacing: 8) {
                                ForEach(group.tags, id: \.self) { tag in
                                    SelectableChip(label: tag, isOn: contextTags.contains(tag)) {
                                        contextTags = toggling(tag, in: contextTags)
                                    }
                                }
                            }
                        }
                    }

                    if entry.source == EntrySource.voice {
                        Label("Captured by voice", systemImage: "mic.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete entry", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.top, 12)
                }
                .padding()
            }
            .keyboardDismissBar()
            .navigationTitle(entry.isCheckIn ? "Check-in" : "Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    context.delete(entry)
                    dismiss()
                }
                Button("Keep", role: .cancel) {}
            }
        }
        .onAppear {
            text = entry.text
            mood = entry.moodScore
            timestamp = entry.timestamp
            emotionWords = entry.emotionWords
            contextTags = entry.contextTags
        }
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mood != nil
    }

    /// Returns the list with `value` added or removed. A pure transform rather
    /// than an `inout` mutation so the chip's escaping tap closure doesn't have
    /// to borrow this view's @State storage.
    private func toggling(_ value: String, in list: [String]) -> [String] {
        var list = list
        if let index = list.firstIndex(of: value) {
            list.remove(at: index)
        } else {
            list.append(value)
        }
        return list
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.text = trimmed
        entry.moodScore = mood
        // Clamp defensively even though the picker's own range already
        // excludes the future/too-far-past — a belt-and-braces guard
        // against a stale binding slipping an out-of-window date through.
        entry.timestamp = EntryEditing.clamp(timestamp)
        entry.emotionWords = emotionWords
        entry.contextTags = contextTags
        entry.sentimentScore = SentimentAnalyzer.score(for: trimmed)
        if trimmed.isEmpty {
            entry.source = EntrySource.checkIn
        }
        dismiss()
    }
}
