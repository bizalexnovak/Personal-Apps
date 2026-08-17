import SwiftUI

/// Dev-only view of the matching pipeline: raw transcript → parsed items →
/// candidates considered → selection reason → plausibility flags → result.
struct DebugLogView: View {
    @ObservedObject private var log = MatchDebugLog.shared

    var body: some View {
        List {
            if log.entries.isEmpty {
                ContentUnavailableView(
                    "No matches logged yet",
                    systemImage: "text.magnifyingglass",
                    description: Text("Log a meal and the full matching trace will appear here.")
                )
            }
            ForEach(log.entries.reversed()) { entry in
                switch entry {
                case .transcript(_, let date, let text):
                    Label {
                        VStack(alignment: .leading) {
                            Text(text).font(.subheadline.bold())
                            Text(date, format: .dateTime.hour().minute().second())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "mic.fill").foregroundStyle(.blue)
                    }
                case .match(let diagnostics):
                    MatchDiagnosticsRow(diagnostics: diagnostics)
                }
            }
        }
        .luxSheetChrome()
        .navigationTitle("Match Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Clear") { log.clear() }
            }
        }
    }
}

private struct MatchDiagnosticsRow: View {
    let diagnostics: MatchDiagnostics
    @State private var showCandidates = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(diagnostics.request.quantity.formatted()) \(diagnostics.request.unit) · \(diagnostics.request.name)")
                .font(.subheadline.bold())

            ForEach(diagnostics.queryAttempts, id: \.self) { attempt in
                Label(attempt, systemImage: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let selected = diagnostics.selectedDescription {
                Text("→ \(selected)").font(.caption)
            }
            Text(diagnostics.selectionReason)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(diagnostics.gramsBasis)
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(diagnostics.flags, id: \.self) { flag in
                Label(flag, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text(diagnostics.resultSummary)
                .font(.caption.monospacedDigit())

            DisclosureGroup("Candidates (\(diagnostics.candidates.count))", isExpanded: $showCandidates) {
                ForEach(diagnostics.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(candidate.description).font(.caption2)
                        Text("\(candidate.dataType) · score \(candidate.nameScore, format: .number.precision(.fractionLength(2))) · \(Int(candidate.kcalPer100g.rounded())) kcal/100g\(candidate.serving.map { " · \($0)" } ?? "")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                }
            }
            .font(.caption2)
        }
        .padding(.vertical, 2)
    }
}
