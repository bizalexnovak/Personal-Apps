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

    /// A parsed item that found no USDA match at all — the user must search
    /// manually, enter macros, or skip it. Never silently saved as zero.
    struct PendingResolution: Identifiable, Equatable {
        let id = UUID()
        var request: FoodItemRequest
    }

    @Published var pendingClarification: PendingClarification?
    @Published var pendingResolution: PendingResolution?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    var parser: MealParsing = ClaudeMealParsingService()
    var logger = MealLoggingService()

    private var rawText = ""
    private var queue: [FoodItemRequest] = []
    private var resolved: [FoodItemRequest] = []
    private var lookupQueue: [FoodItemRequest] = []
    private var lookedUp: [(request: FoodItemRequest, match: NutritionMatch)] = []
    private var context: ModelContext?

    var isCapturing: Bool {
        isWorking || pendingClarification != nil || pendingResolution != nil
    }

    // MARK: - Entry point

    func begin(text: String, in context: ModelContext) async {
        guard !isCapturing else { return }
        self.context = context
        rawText = text
        queue = []
        resolved = []
        lookupQueue = []
        lookedUp = []
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

    // MARK: - Manual-resolution card responses (no-match fallback)

    /// User resolved the unmatched item via manual USDA search or manual
    /// macro entry — `match` carries the chosen/entered values.
    func resolveManually(_ match: NutritionMatch) async {
        guard pendingResolution != nil, !lookupQueue.isEmpty else { return }
        lookedUp.append((request: lookupQueue.removeFirst(), match: match))
        pendingResolution = nil
        await advanceLookups()
    }

    /// User chose to drop the unmatched item from the meal.
    func skipUnmatchedItem() async {
        guard pendingResolution != nil, !lookupQueue.isEmpty else { return }
        lookupQueue.removeFirst()
        pendingResolution = nil
        await advanceLookups()
    }

    /// Abandon the whole meal without saving anything.
    func cancelMeal() {
        queue = []
        resolved = []
        lookupQueue = []
        lookedUp = []
        rawText = ""
        pendingClarification = nil
        pendingResolution = nil
        isWorking = false
    }

    // MARK: - Flow

    /// Phase A: walk parsed items, pausing on any that need clarification.
    private func advance() async {
        while let next = queue.first {
            if let prompt = Self.clarificationPrompt(for: next) {
                isWorking = false // idle while waiting for the user's tap
                pendingClarification = prompt
                return
            }
            resolved.append(queue.removeFirst())
        }
        lookupQueue = resolved
        resolved = []
        await advanceLookups()
    }

    /// Phase B: look up each resolved item. A lookup that finds nothing (or
    /// errors) pauses on a manual-resolution card instead of saving zeros.
    private func advanceLookups() async {
        while let next = lookupQueue.first {
            isWorking = true
            do {
                let match = try await logger.nutrition.lookup(next)
                lookedUp.append((request: lookupQueue.removeFirst(), match: match))
            } catch {
                isWorking = false // idle while waiting for the user
                pendingResolution = PendingResolution(request: next)
                return
            }
        }
        await finish()
    }

    private func finish() async {
        defer { isWorking = false }
        guard let context else { return }
        guard !lookedUp.isEmpty else {
            errorMessage = "Nothing to log."
            return
        }
        isWorking = true
        do {
            try logger.saveResolved(lookedUp, rawText: rawText, in: context)
            rawText = ""
            lookedUp = []
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
