import Foundation
import os

/// One candidate the matcher considered, as shown in the debug view.
struct CandidateSummary: Identifiable, Equatable {
    let id = UUID()
    var description: String
    var dataType: String
    var nameScore: Double
    /// Energy as reported by the search result (per 100 g/100 ml) — makes
    /// mislabeled or wrong-product-line entries visible at a glance.
    var kcalPer100g: Double
    var serving: String?
}

/// Full trace of one lookup: parsed item → candidates → selection → result.
struct MatchDiagnostics: Identifiable, Equatable {
    let id = UUID()
    var timestamp = Date()
    var request: FoodItemRequest
    /// Every USDA query sent for this item and its result count, in order.
    var queryAttempts: [String] = []
    var candidates: [CandidateSummary]
    var selectedDescription: String?
    var selectionReason: String
    var gramsBasis: String
    var flags: [String]
    var resultSummary: String
}

/// In-memory ring buffer of recent matching activity, mirrored to the console
/// via os.Logger (filter on subsystem com.alexnovak.macrolog in Console.app or
/// the Xcode console). Dev tooling only — nothing here is persisted.
@MainActor
final class MatchDebugLog: ObservableObject {
    static let shared = MatchDebugLog()

    enum Entry: Identifiable, Equatable {
        case transcript(id: UUID, date: Date, text: String)
        case match(MatchDiagnostics)

        var id: UUID {
            switch self {
            case .transcript(let id, _, _): return id
            case .match(let diagnostics): return diagnostics.id
            }
        }
    }

    @Published private(set) var entries: [Entry] = []

    private let logger = Logger(subsystem: "com.alexnovak.macrolog", category: "matching")
    private let maxEntries = 200

    func record(transcript: String) {
        append(.transcript(id: UUID(), date: Date(), text: transcript))
        logger.debug("transcript: \(transcript, privacy: .public)")
    }

    func record(_ diagnostics: MatchDiagnostics) {
        append(.match(diagnostics))
        let candidates = diagnostics.candidates
            .map { String(format: "  [%.2f] %@ (%@) %.0f kcal/100g%@", $0.nameScore, $0.description, $0.dataType, $0.kcalPer100g, $0.serving.map { " serving: \($0)" } ?? "") }
            .joined(separator: "\n")
        logger.debug("""
        parsed: \(diagnostics.request.quantity, privacy: .public) \(diagnostics.request.unit, privacy: .public) '\(diagnostics.request.name, privacy: .public)'
        queries: \(diagnostics.queryAttempts.joined(separator: " | "), privacy: .public)
        candidates:
        \(candidates, privacy: .public)
        selected: \(diagnostics.selectedDescription ?? "none", privacy: .public)
        reason: \(diagnostics.selectionReason, privacy: .public)
        grams: \(diagnostics.gramsBasis, privacy: .public)
        flags: \(diagnostics.flags.isEmpty ? "none" : diagnostics.flags.joined(separator: "; "), privacy: .public)
        result: \(diagnostics.resultSummary, privacy: .public)
        """)
    }

    func clear() {
        entries.removeAll()
    }

    private func append(_ entry: Entry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}
