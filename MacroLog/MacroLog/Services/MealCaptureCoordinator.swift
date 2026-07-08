import Foundation
import SwiftData

/// Drives the capture flow: parse the transcript, look up every item in the
/// background, then publish one ReviewSession that the Match Review Screen
/// renders — transcript on top, one card per item. Nothing is written to
/// SwiftData until the user confirms/edits every card and taps Save All.
@MainActor
final class MealCaptureCoordinator: ObservableObject {
    enum ReviewStatus: Equatable {
        case needsReview
        case confirmed
        case edited
    }

    struct ReviewItem: Identifiable {
        let id = UUID()
        var request: FoodItemRequest
        /// nil = USDA found nothing; the card blocks Save All until resolved.
        var match: NutritionMatch?
        /// Quick-pick interpretations (Claude's clarification options, or the
        /// local vague-unit fallbacks) shown as chips on the card.
        var clarificationQuestion: String?
        var options: [ClarificationOption]
        var status: ReviewStatus

        var needsAttention: Bool {
            match == nil || match?.confidence == MatchConfidence.low
        }
    }

    struct ReviewSession: Identifiable {
        let id = UUID()
        var rawText: String
        var items: [ReviewItem]
    }

    @Published var review: ReviewSession?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    var parser: MealParsing = ClaudeMealParsingService()
    var logger = MealLoggingService()

    private var context: ModelContext?

    var isCapturing: Bool { isWorking || review != nil }

    var canSaveAll: Bool {
        guard let review, !review.items.isEmpty else { return false }
        return review.items.allSatisfy { $0.status != .needsReview && $0.match != nil }
    }

    // MARK: - Entry point

    func begin(text: String, in context: ModelContext) async {
        guard !isCapturing else { return }
        self.context = context
        isWorking = true
        MatchDebugLog.shared.record(transcript: text)

        let requests: [FoodItemRequest]
        do {
            requests = try await parser.parse(text)
        } catch {
            errorMessage = error.localizedDescription
            isWorking = false
            return
        }

        var items: [ReviewItem] = []
        for request in requests {
            let hints = Self.clarificationHints(for: request)
            // A failed lookup is represented as match == nil — the card opens
            // in search mode and blocks Save All; zeros are never fabricated.
            let match = await resolveMatch(for: request, in: context)
            items.append(ReviewItem(
                request: request,
                match: match,
                clarificationQuestion: hints?.question,
                options: hints?.options ?? [],
                status: .needsReview
            ))
        }
        isWorking = false

        guard !items.isEmpty else {
            errorMessage = "Couldn't find any food items in that."
            return
        }
        review = ReviewSession(rawText: text, items: items)
    }

    // MARK: - Card actions

    /// ✅ Confirm — accept the matched values as-is. No-op while unmatched.
    func confirm(_ itemID: UUID) {
        updateItem(itemID) { item in
            if item.match != nil {
                item.status = .confirmed
            }
        }
    }

    /// ✏️ Edit — user-entered macros replace the match (verified values).
    func applyEdit(_ itemID: UUID, calories: Double, protein: Double, carbs: Double, fat: Double) {
        updateItem(itemID) { item in
            item.match = NutritionMatch(
                matchedDescription: item.match?.matchedDescription ?? "Manual entry",
                calories: calories, protein: protein, carbs: carbs, fat: fat,
                confidence: MatchConfidence.high
            )
            item.status = .edited
        }
    }

    /// 🔍 Search — user explicitly picked a different USDA food; recompute
    /// macros for the item's quantity/unit, mark it confirmed, and REMEMBER the
    /// correction so future logs of this phrase reuse this food automatically.
    func applyPickedFood(_ itemID: UUID, food: USDAFood) {
        guard let item = review?.items.first(where: { $0.id == itemID }) else { return }
        let match = USDANutritionLookupService.evaluate(for: item.request, food: food, nameScore: 1.0).match
        if let context {
            RememberedMatchStore.remember(phrase: item.request.name, food: food, in: context)
        }
        updateItem(itemID) { item in
            item.match = match
            item.status = .confirmed
        }
    }

    /// Option chip tapped — swap in the resolved interpretation and re-run
    /// the lookup for it. The card returns to needs-review with new macros.
    func chooseOption(_ itemID: UUID, option: ClarificationOption) async {
        guard let context, review != nil else { return }
        isWorking = true
        let newRequest = FoodItemRequest(name: option.name, quantity: option.quantity, unit: option.unit)
        let match = await resolveMatch(for: newRequest, in: context)
        isWorking = false
        updateItem(itemID) { item in
            item.request = newRequest
            item.match = match
            item.clarificationQuestion = nil
            item.options = []
            item.status = .needsReview
        }
    }

    /// A remembered correction wins over a fresh search; otherwise fall through
    /// to the normal USDA lookup. A nil result means no match (never zeros).
    private func resolveMatch(for request: FoodItemRequest, in context: ModelContext) async -> NutritionMatch? {
        if let remembered = RememberedMatchStore.lookup(phrase: request.name, in: context) {
            return USDANutritionLookupService.evaluate(for: request, food: remembered, nameScore: 1.0).match
        }
        return try? await logger.nutrition.lookup(request)
    }

    /// Drop an item from the meal (e.g. a hallucinated parse or an unmatched
    /// extra) so it doesn't block Save All.
    func removeItem(_ itemID: UUID) {
        review?.items.removeAll { $0.id == itemID }
    }

    func cancelReview() {
        review = nil
        isWorking = false
    }

    /// Search passthrough for the card's inline USDA search pane.
    func searchFoods(query: String) async -> [USDAFood] {
        (try? await logger.nutrition.search(query: query)) ?? []
    }

    // MARK: - Save

    func saveAll() async {
        guard canSaveAll, let context, let session = review else { return }
        isWorking = true
        defer { isWorking = false }
        let entries = session.items.compactMap { item in
            item.match.map { (request: item.request, match: $0) }
        }
        do {
            try logger.saveResolved(entries, rawText: session.rawText, in: context)
            review = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func updateItem(_ itemID: UUID, _ transform: (inout ReviewItem) -> Void) {
        guard var session = review,
              let index = session.items.firstIndex(where: { $0.id == itemID })
        else { return }
        transform(&session.items[index])
        review = session
    }

    /// Claude's clarification flag is the primary source; a locally detected
    /// vague unit is the safety net. Either way the interpretations become
    /// tap-to-resolve chips on the review card.
    static func clarificationHints(for item: FoodItemRequest) -> (question: String, options: [ClarificationOption])? {
        if item.needsClarification == true, let options = item.options, !options.isEmpty {
            return (item.clarificationQuestion ?? "Can you be more specific?", options)
        }
        if case .vague(let word) = USDANutritionLookupService.classifyUnit(item.unit) {
            return ("How much \(item.name) was it?", fallbackOptions(for: item, vagueWord: word))
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
