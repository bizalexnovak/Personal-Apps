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
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(.subheadline)

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
        }
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mood != nil
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.text = trimmed
        entry.moodScore = mood
        entry.timestamp = timestamp
        entry.sentimentScore = SentimentAnalyzer.score(for: trimmed)
        if trimmed.isEmpty {
            entry.source = EntrySource.checkIn
        }
        dismiss()
    }
}
