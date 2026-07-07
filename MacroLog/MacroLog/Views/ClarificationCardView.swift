import SwiftUI

/// Tap-only clarification card shown when a parsed item is too vague to log.
/// Presents 2-4 concrete interpretations, a "type it instead" fallback, and a
/// "keep as I said it" escape hatch (which logs the item low-confidence).
struct ClarificationCardView: View {
    let pending: MealCaptureCoordinator.PendingClarification
    @ObservedObject var coordinator: MealCaptureCoordinator

    @State private var customText = ""
    @State private var showCustomField = false
    @FocusState private var customFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pending.question)
                            .font(.title3.bold())
                        Text("You said: \(pending.item.quantity.formatted()) \(pending.item.unit) · \(pending.item.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        ForEach(pending.options) { option in
                            Button {
                                Task { await coordinator.choose(option) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.body.weight(.medium))
                                    Text("\(option.quantity.formatted()) \(option.unit) · \(option.name)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if showCustomField {
                        HStack {
                            TextField("Describe it exactly…", text: $customText)
                                .textFieldStyle(.roundedBorder)
                                .focused($customFieldFocused)
                                .onSubmit(submitCustom)
                            Button("Go", action: submitCustom)
                                .disabled(customText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button("Type it instead…") {
                            showCustomField = true
                            customFieldFocused = true
                        }
                        .font(.subheadline)
                    }

                    Button("Keep as I said it (mark for review)") {
                        Task { await coordinator.keepAsHeard() }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Quick question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel meal", role: .destructive) {
                        coordinator.cancelMeal()
                    }
                }
            }
        }
    }

    private func submitCustom() {
        let text = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { await coordinator.chooseCustom(text) }
    }
}
