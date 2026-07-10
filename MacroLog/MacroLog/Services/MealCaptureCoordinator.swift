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

    /// Snapshot of quantity + macros at scaleFactor 1.0 so the portion slider
    /// is absolute (drag to 2× then back to 1× restores the original values
    /// instead of compounding). Reset whenever the match is replaced.
    struct ScaleBaseline {
        var quantity: Double
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
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
        /// Current portion multiplier (1.0 = as matched). Driven by the slider.
        var scaleFactor: Double = 1
        var scaleBaseline: ScaleBaseline?

        var needsAttention: Bool {
            match == nil || match?.confidence == MatchConfidence.low
        }

        /// Re-anchor the slider to the current match/quantity and reset to 1×.
        /// Call after the match is first set or later replaced.
        mutating func captureScaleBaseline() {
            guard let m = match else { scaleBaseline = nil; return }
            scaleBaseline = ScaleBaseline(
                quantity: request.quantity,
                calories: m.calories, protein: m.protein, carbs: m.carbs, fat: m.fat
            )
            scaleFactor = 1
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
    /// Set after a nutrition label is scanned: the macros are known but the
    /// product name isn't (it's rarely on the label), so the app asks the user
    /// to say the name before building the review.
    @Published var pendingLabel: LabelNutrition?

    var parser: MealParsing = ClaudeMealParsingService()
    var labelScanner: LabelScanning = ClaudeLabelScanningService()
    var logger = MealLoggingService()

    private var context: ModelContext?

    var isCapturing: Bool { isWorking || review != nil || pendingLabel != nil }

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
            // Water is tracked in ounces, not macros — skip USDA entirely and
            // give it a 0-calorie confirmed-able match.
            if WaterConversion.isWater(request.name) {
                let oz = WaterConversion.ounces(quantity: request.quantity, unit: request.unit)
                items.append(ReviewItem(
                    request: request,
                    match: NutritionMatch(
                        matchedDescription: "Water · \(Int(oz.rounded())) oz",
                        calories: 0, protein: 0, carbs: 0, fat: 0,
                        confidence: MatchConfidence.high
                    ),
                    clarificationQuestion: nil,
                    options: [],
                    status: .needsReview
                ))
                continue
            }
            // Explicit macros spoken by the user win over any USDA lookup.
            if let spoken = Self.explicitMacroMatch(for: request) {
                items.append(ReviewItem(
                    request: request, match: spoken,
                    clarificationQuestion: nil, options: [], status: .needsReview
                ))
                continue
            }
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
        for i in items.indices { items[i].captureScaleBaseline() }
        review = ReviewSession(rawText: text, items: items)
    }

    /// Scan Label path, step 1: read the macros straight off a photographed
    /// nutrition label (authoritative — no USDA lookup). The product name is
    /// rarely on the facts panel, so instead of building the review here we
    /// stash the label and let CaptureView ask the user to say the name.
    func beginFromLabel(imageData: Data, in context: ModelContext) async {
        guard !isCapturing else { return }
        self.context = context
        isWorking = true

        let label: LabelNutrition
        do {
            label = try await labelScanner.scan(imageData: imageData)
        } catch {
            errorMessage = error.localizedDescription
            isWorking = false
            return
        }
        isWorking = false
        pendingLabel = label
    }

    /// Scan Label path, step 2: combine the authoritative label macros with the
    /// spoken product name, then build the one-item review. An empty spoken
    /// name falls back to whatever the label read (or a generic placeholder).
    func finishLabel(name spokenName: String, in context: ModelContext) {
        guard let label = pendingLabel else { return }
        self.context = context

        let cleaned = Self.cleanSpokenName(spokenName)
        let name = !cleaned.isEmpty ? cleaned
            : (label.name.isEmpty ? "Scanned item" : label.name)
        let description = label.servingSize.isEmpty
            ? name
            : "\(name) · \(label.servingSize)"
        let match = NutritionMatch(
            matchedDescription: description,
            calories: label.calories, protein: label.protein,
            carbs: label.carbs, fat: label.fat,
            confidence: MatchConfidence.high // label values are authoritative
        )
        var item = ReviewItem(
            request: FoodItemRequest(name: name, quantity: 1, unit: "serving"),
            match: match,
            clarificationQuestion: nil,
            options: [],
            status: .needsReview
        )
        item.captureScaleBaseline()
        MatchDebugLog.shared.record(transcript: "Scanned label: \(name)")
        pendingLabel = nil
        review = ReviewSession(rawText: "Scanned label: \(name)", items: [item])
    }

    /// Trim conversational lead-ins from a spoken product name so "it's a Quest
    /// bar" becomes "Quest bar".
    static func cleanSpokenName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ".!?,"))
        let lowered = s.lowercased()
        // Longest prefixes first so "it's a " wins over "it's ".
        let prefixes = [
            "it is called ", "it's called ", "the name is ", "its called ",
            "it is a ", "it's a ", "this is a ", "that is a ", "that's a ",
            "this is ", "that is ", "that's ", "it is ", "it's ", "its ",
            "call it ", "name is ", "a ",
        ]
        for p in prefixes where lowered.hasPrefix(p) {
            s = String(s.dropFirst(p.count))
            break
        }
        return s.trimmingCharacters(in: .whitespaces)
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

    /// A match built from macros the user spoke; missing calories are derived
    /// from protein/carbs/fat (4/4/9). Returns nil if no macro was given.
    static func explicitMacroMatch(for request: FoodItemRequest) -> NutritionMatch? {
        guard request.hasExplicitMacros else { return nil }
        let p = request.protein ?? 0
        let c = request.carbs ?? 0
        let f = request.fat ?? 0
        let calories = request.calories ?? (p * 4 + c * 4 + f * 9)
        return NutritionMatch(
            matchedDescription: "\(request.name) (your numbers)",
            calories: calories, protein: p, carbs: c, fat: f,
            confidence: MatchConfidence.high
        )
    }

    /// Rename an item on the review card.
    func rename(_ itemID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        updateItem(itemID) { $0.request.name = trimmed }
    }

    /// Set the portion multiplier from the slider. Absolute (relative to the
    /// captured baseline), so 2× then 1× returns to the original values.
    func setScale(_ itemID: UUID, factor: Double) {
        updateItem(itemID) { item in
            guard let base = item.scaleBaseline else { return }
            let f = max(0.1, factor)
            item.scaleFactor = f
            item.request.quantity = base.quantity * f
            if var m = item.match {
                m.calories = base.calories * f
                m.protein = base.protein * f
                m.carbs = base.carbs * f
                m.fat = base.fat * f
                item.match = m
            }
            if item.status == .confirmed { item.status = .edited }
        }
    }

    /// ✏️ Edit water — set the amount directly in ounces.
    func applyWaterEdit(_ itemID: UUID, ounces: Double) {
        updateItem(itemID) { item in
            item.request.quantity = ounces
            item.request.unit = "oz"
            item.match = NutritionMatch(
                matchedDescription: "Water · \(Int(ounces.rounded())) oz",
                calories: 0, protein: 0, carbs: 0, fat: 0,
                confidence: MatchConfidence.high
            )
            item.status = .edited
            item.captureScaleBaseline()
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
            item.captureScaleBaseline()
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
            item.captureScaleBaseline()
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
            item.captureScaleBaseline()
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
        pendingLabel = nil
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
