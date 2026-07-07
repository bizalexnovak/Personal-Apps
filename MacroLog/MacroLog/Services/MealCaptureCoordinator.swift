import Foundation
import SwiftData

/// State machine for the capture flow: parse the raw text, walk the parsed
/// items, pause on any item that needs clarification (showing a tap-only
/// card), and only after every item is resolved run lookups and save.
/// Nothing touches SwiftData while a clarification is pending.
@MainActor
final class MealCaptureCoordinator: ObservableObject {
    struct PendingClarification: Identifiable, Equatable {
        let id = UUID()
        var item: FoodItemRequest
        var question: String
        var options: [ClarificationOption]
    }

    @Published var pendingClarification: PendingClarification?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    var parser: MealParsing = ClaudeMealParsingService()
    var logger = MealLoggingService()

    private var rawText = ""
    private var queue: [FoodItemRequest] = []
    private var resolved: [FoodItemRequest] = []
    private var context: ModelContext?

    var isCapturing: Bool { isWorking || pendingClarification != nil }

    // MARK: - Entry point

    func begin(text: String, in context: ModelContext) async {
        guard !isCapturing else { return }
        self.context = context
        rawText = text
        queue = []
        resolved = []
        isWorking = true
        MatchDebugLog.shared.record(transcript: text)
        do {
            queue = try await parser.parse(text)
        } catch {
            errorMessage = error.localizedDescription
            isWorking = false
            return
        }
        await advance()
    }

    // MARK: - Card responses

    /// User tapped one of the suggested options — it replaces the vague item.
    func choose(_ option: ClarificationOption) async {
        guard pendingClarification != nil, !queue.isEmpty else { return }
        queue.removeFirst()
        resolved.append(FoodItemRequest(name: option.name, quantity: option.quantity, unit: option.unit))
        pendingClarification = nil
        await advance()
    }

    /// User typed a custom description instead — re-parse it. The result goes
    /// to the front of the queue, so if it's still vague we ask again.
    func chooseCustom(_ text: String) async {
        guard pendingClarification != nil, !queue.isEmpty else { return }
        let original = queue.removeFirst()
        pendingClarification = nil
        isWorking = true
        do {
            let reparsed = try await parser.parse(text)
            queue.insert(contentsOf: reparsed, at: 0)
        } catch {
            // Couldn't parse the custom text — keep the original item; the
            // lookup layer will flag it low confidence.
            errorMessage = error.localizedDescription
            resolved.append(original)
        }
        await advance()
    }

    /// User declined to clarify — log the item as heard. The vague unit will
    /// come out low-confidence from the lookup layer and show the ⚠️ badge.
    func keepAsHeard() async {
        guard pendingClarification != nil, !queue.isEmpty else { return }
        resolved.append(queue.removeFirst())
        pendingClarification = nil
        await advance()
    }

    /// Abandon the whole meal without saving anything.
    func cancelMeal() {
        queue = []
        resolved = []
        rawText = ""
        pendingClarification = nil
        isWorking = false
    }

    // MARK: - Flow

    private func advance() async {
        while let next = queue.first {
            if let prompt = Self.clarificationPrompt(for: next) {
                isWorking = false // idle while waiting for the user's tap
                pendingClarification = prompt
                return
            }
            resolved.append(queue.removeFirst())
        }
        await finish()
    }

    private func finish() async {
        defer { isWorking = false }
        guard let context, !resolved.isEmpty else {
            if resolved.isEmpty { errorMessage = "Nothing to log." }
            return
        }
        isWorking = true
        do {
            try await logger.save(requests: resolved, rawText: rawText, in: context)
            rawText = ""
            resolved = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Prompt construction

    /// Claude's flag is the primary source; a locally detected vague unit is
    /// the safety net so "a bowl of X" can never slip through unclarified
    /// even if the parser forgot to flag it.
    static func clarificationPrompt(for item: FoodItemRequest) -> PendingClarification? {
        if item.needsClarification == true, let options = item.options, !options.isEmpty {
            return PendingClarification(
                item: item,
                question: item.clarificationQuestion ?? "Can you be more specific?",
                options: options
            )
        }
        if case .vague(let word) = USDANutritionLookupService.classifyUnit(item.unit) {
            return PendingClarification(
                item: item,
                question: "How much \(item.name) was it?",
                options: fallbackOptions(for: item, vagueWord: word)
            )
        }
        return nil
    }

    /// Generic size options used when the parser flagged nothing but the unit
    /// is a vague container word. Scaled by the stated quantity ("2 bags").
    static func fallbackOptions(for item: FoodItemRequest, vagueWord: String) -> [ClarificationOption] {
        let multiplier = max(item.quantity, 1)
        let bases: [(String, Double, String)]
        switch vagueWord {
        case "bag":
            bases = [
                ("Snack bag (about 1 oz)", 28, "g"),
                ("Single-serve bag (about 3 oz)", 85, "g"),
                ("Half a sharing bag (about 5 oz)", 140, "g"),
            ]
        case "bowl":
            bases = [
                ("Small bowl (1 cup)", 1, "cup"),
                ("Medium bowl (1.5 cups)", 1.5, "cup"),
                ("Large bowl (2 cups)", 2, "cup"),
            ]
        case "handful":
            bases = [
                ("Small handful (about 20 g)", 20, "g"),
                ("Handful (about 40 g)", 40, "g"),
                ("Two handfuls (about 80 g)", 80, "g"),
            ]
        default: // some, bit, few, couple, little...
            bases = [
                ("Small portion (about 50 g)", 50, "g"),
                ("Medium portion (about 100 g)", 100, "g"),
                ("Large portion (about 200 g)", 200, "g"),
            ]
        }
        return bases.map { label, amount, unit in
            ClarificationOption(label: label, name: item.name, quantity: amount * multiplier, unit: unit)
        }
    }
}
