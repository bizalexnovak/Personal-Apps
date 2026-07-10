import SwiftUI

/// The Log tab: a capture surface, not a list. Voice by default with a
/// camera-app-style switch to Scan, plus a keyboard button in the corner to
/// type instead. Tapping the big button launches the selected capture mode
/// (the review + saving happens in CaptureView, and logged meals are viewed and
/// edited on the Today tab).
struct MealListView: View {
    @Environment(\.metricPalette) private var palette

    private enum Mode: String, CaseIterable, Identifiable {
        case voice, scan
        var id: String { rawValue }
        var title: String { self == .voice ? "Voice" : "Scan" }
        var icon: String { self == .voice ? "mic.fill" : "camera.fill" }
        var caption: String {
            self == .voice
                ? "Tap and describe what you ate."
                : "Tap to scan a nutrition label."
        }
    }

    @State private var mode: Mode = .voice
    @State private var showTypeSheet = false
    @State private var typedText = ""

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()

                Button(action: startCurrentMode) {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.15))
                                .frame(width: 168, height: 168)
                            Circle()
                                .strokeBorder(accent.opacity(0.6), lineWidth: 5)
                                .frame(width: 132, height: 132)
                            Circle()
                                .fill(accent)
                                .frame(width: 104, height: 104)
                            Image(systemName: mode.icon)
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text(mode.caption)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: mode)

                Spacer()

                modeSwitcher
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTypeSheet = true
                    } label: {
                        Image(systemName: "keyboard")
                    }
                    .accessibilityLabel("Type instead")
                }
            }
            .sheet(isPresented: $showTypeSheet) { typeSheet }
        }
    }

    private var accent: Color {
        mode == .voice ? palette.calories : palette.carbs
    }

    // MARK: Mode switcher (camera-app style)

    private var modeSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { mode = option }
                } label: {
                    Text(option.title.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(0.5)
                        .foregroundStyle(mode == option ? accent : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(mode == option ? accent.opacity(0.15) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(.quaternary.opacity(0.4)))
    }

    // MARK: Type sheet

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
                    Button("Cancel") {
                        typedText = ""
                        showTypeSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { submitTyped() }
                        .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Actions

    private func startCurrentMode() {
        switch mode {
        case .voice: PendingMealStore.shared.requestVoice()
        case .scan: PendingMealStore.shared.requestScan()
        }
    }

    private func submitTyped() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedText = ""
        showTypeSheet = false
        PendingMealStore.shared.requestText(text)
    }
}
