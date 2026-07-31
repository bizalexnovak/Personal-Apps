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
        var micros: Micronutrients
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
                calories: m.calories, protein: m.protein, carbs: m.carbs, fat: m.fat,
                micros: m.micros
            )
            scaleFactor = 1
        }
    }

    struct ReviewSession: Identifiable {
        let id = UUID()
        var rawText: String
        var items: [ReviewItem]
    }

    /// What the coordinator is currently doing while `isWorking`, so the UI can
    /// show the right status text regardless of which capture mode is selected
    /// (typing a meal while the Log tab happens to be in Scan mode must still
    /// say "Analyzing your meal…", not "Reading the label…").
    enum WorkKind {
        case parsingText, readingLabel, estimatingDish

        /// The ONE mapping from operation to spinner text — every status
        /// string the capture flow shows comes from here.
        var text: String {
            switch self {
            case .parsingText: return "Analyzing your meal…"
            case .readingLabel: return "Reading the label…"
            case .estimatingDish: return "Estimating from your photo…"
            }
        }
    }

    @Published var review: ReviewSession?
    @Published private(set) var isWorking = false
    @Published private(set) var workKind: WorkKind = .parsingText
    @Published var errorMessage: String?
    /// Non-blocking banner on the review screen (e.g. "no connection —
    /// understood on device"), unlike errorMessage which is an alert.
    @Published var notice: String?

    /// Status text for the analyzing spinner, driven by the in-flight operation.
    var workingText: String { workKind.text }
    /// The day the meal under review will be saved to. Defaults to now; the
    /// review screen lets the user back-date it to a previous day.
    @Published var logDate = Date()
    /// Set after a nutrition label is scanned: the macros are known but the
    /// product name isn't (it's rarely on the label), so the app asks the user
    /// to say the name before building the review.
    @Published var pendingLabel: LabelNutrition?

    var parser: MealParsing = ClaudeMealParsingService()
    var labelScanner: LabelScanning = ClaudeLabelScanningService()
    var dishEstimator: DishEstimating = ClaudeDishEstimationService()
    var logger = MealLoggingService()
    var openFoodFacts = OpenFoodFactsService()

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
        workKind = .parsingText
        isWorking = true
        notice = nil
        logDate = Date()
        MatchDebugLog.shared.record(transcript: text)

        let requests: [FoodItemRequest]
        do {
            requests = try await parser.parse(text)
        } catch {
            // No connection is not a dead end: parse on device instead, so an
            // entry can always be created. Water, supplements, spoken macros,
            // and remembered foods resolve fully offline; the rest become
            // unmatched cards the user completes by hand.
            if Self.isConnectivityError(error) {
                requests = LocalMealParser.parse(text)
                // A timeout can be a slow-but-reachable server, not a dead
                // zone — say so instead of claiming "no connection".
                notice = (error as? URLError)?.code == .timedOut
                    ? "Slow or no connection — understood on device instead. Double-check the numbers, or re-log later for a full parse."
                    : "No connection — understood on device. Water and supplements log normally; tap Edit on anything unmatched to type its numbers."
            } else {
                errorMessage = error.localizedDescription
                isWorking = false
                return
            }
        }

        var items: [ReviewItem] = []
        for request in requests {
            // Explicit macros spoken by the user win over EVERY shortcut and
            // lookup — checked first so "creatine gummies, 150 calories" keeps
            // its stated numbers instead of being zeroed by a name match.
            if let spoken = Self.explicitMacroMatch(for: request) {
                items.append(Self.directItem(request, spoken))
                continue
            }
            // Bare supplements (creatine, caffeine pills) skip USDA — a food
            // search would mismatch them; the dose goes on the micronutrient
            // record instead.
            if let supplement = SupplementConversion.match(for: request) {
                items.append(Self.directItem(request, supplement))
                continue
            }
            // Water is tracked in ounces, not macros — skip USDA entirely and
            // give it a 0-calorie confirmed-able match.
            if WaterConversion.isWater(request.name) {
                let oz = WaterConversion.ounces(quantity: request.quantity, unit: request.unit)
                items.append(Self.directItem(request, NutritionMatch(
                    matchedDescription: "Water · \(Int(oz.rounded())) oz",
                    calories: 0, protein: 0, carbs: 0, fat: 0,
                    confidence: MatchConfidence.high
                )))
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
        workKind = .readingLabel
        isWorking = true
        notice = nil
        logDate = Date()

        let label: LabelNutrition
        do {
            label = try await labelScanner.scan(imageData: imageData)
        } catch {
            // Vision has no on-device fallback — but a dead zone shouldn't
            // read as a mysterious failure; point at the paths that DO work.
            errorMessage = Self.isConnectivityError(error)
                ? "No connection — reading a label needs the internet. Voice and typing still work offline: say or type the label's numbers instead."
                : error.localizedDescription
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
            confidence: MatchConfidence.high, // label values are authoritative
            micros: label.micronutrients
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
        // Every scanned label feeds the food database (deduped), so this
        // product matches instantly next time — for everyone, once synced.
        CustomFoodStore.addFromScan(name: name, label: label, in: context)
        pendingLabel = nil
        review = ReviewSession(rawText: "Scanned label: \(name)", items: [item])
    }

    /// Photograph-a-dish path: send the meal photo to Claude for a nutrition
    /// estimate, then build a review with one card per component. Every item is
    /// an estimate, so they're all marked low-confidence for the user to check.
    func beginFromDishPhoto(imageData: Data, in context: ModelContext) async {
        guard !isCapturing else { return }
        self.context = context
        workKind = .estimatingDish
        isWorking = true
        notice = nil
        logDate = Date()

        let dish: EstimatedDish
        do {
            dish = try await dishEstimator.estimate(imageData: imageData)
        } catch {
            errorMessage = Self.isConnectivityError(error)
                ? "No connection — dish estimates need the internet. Voice and typing still work offline."
                : error.localizedDescription
            isWorking = false
            return
        }
        isWorking = false

        let items: [ReviewItem] = dish.items.map { estimate in
            var item = ReviewItem(
                request: FoodItemRequest(name: estimate.name, quantity: estimate.quantity, unit: estimate.unit),
                match: NutritionMatch(
                    matchedDescription: "Estimated from photo",
                    calories: estimate.calories, protein: estimate.protein,
                    carbs: estimate.carbs, fat: estimate.fat,
                    confidence: MatchConfidence.low // estimates always need a look
                ),
                clarificationQuestion: nil,
                options: [],
                status: .needsReview
            )
            item.captureScaleBaseline()
            return item
        }

        guard !items.isEmpty else {
            errorMessage = "Couldn't find any food in that photo."
            return
        }
        MatchDebugLog.shared.record(transcript: "Photo of a dish (\(items.count) items)")
        review = ReviewSession(rawText: "Photo of a dish", items: items)
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

    /// True for errors that mean "the network is unreachable/unusable right
    /// now" — the cue to fall back to on-device parsing rather than fail.
    /// The TLS/certificate codes cover captive portals (hotel/plane Wi-Fi
    /// that intercepts requests before login), which present as security
    /// errors rather than no-connection errors.
    private static func isConnectivityError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff,
             .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .appTransportSecurityRequiresSecureConnection:
            return true
        default:
            return false
        }
    }

    /// A review card for an item resolved without USDA (explicit macros,
    /// supplement dose, water) — one construction site for all three paths.
    private static func directItem(_ request: FoodItemRequest, _ match: NutritionMatch) -> ReviewItem {
        ReviewItem(
            request: request, match: match,
            clarificationQuestion: nil, options: [], status: .needsReview
        )
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
                m.micros = base.micros.scaled(by: f)
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

    /// ✏️ Micros — user-entered micronutrients replace the match's record
    /// before save (fixing a mis-read label, or adding what a match lacked).
    /// A needs-review card still needs its Confirm/Edit — micros alone don't
    /// unlock Save All — but like the portion slider, editing micros on an
    /// already-confirmed card downgrades it to edited.
    func applyMicrosEdit(_ itemID: UUID, micros: Micronutrients) {
        updateItem(itemID) { item in
            guard var match = item.match else { return }
            match.micros = micros
            item.match = match
            if item.status == .confirmed { item.status = .edited }
            item.captureScaleBaseline()
        }
    }

    /// ✏️ Edit — user-entered macros replace the match (verified values).
    func applyEdit(_ itemID: UUID, calories: Double, protein: Double, carbs: Double, fat: Double) {
        updateItem(itemID) { item in
            item.match = NutritionMatch(
                matchedDescription: item.match?.matchedDescription ?? "Manual entry",
                calories: calories, protein: protein, carbs: carbs, fat: fat,
                confidence: MatchConfidence.high,
                micros: item.match?.micros ?? .empty // keep recorded micros
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
        workKind = .parsingText // a text-based re-lookup, whatever mode captured it
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

    /// Match resolution ladder: a remembered correction wins outright, then
    /// the app's own food database (scanned labels, imported sheets, community
    /// contributions — instant and offline), then the USDA API, and finally
    /// Open Food Facts for branded products USDA lacks. A nil result means no
    /// match (never zeros).
    private func resolveMatch(for request: FoodItemRequest, in context: ModelContext) async -> NutritionMatch? {
        if let remembered = RememberedMatchStore.lookup(phrase: request.name, in: context) {
            return USDANutritionLookupService.evaluate(for: request, food: remembered, nameScore: 1.0).match
        }
        if let custom = CustomFoodStore.match(for: request, in: context) {
            MatchDebugLog.shared.record(transcript: "Matched \"\(request.name)\" from the food database")
            return custom
        }
        if let usda = try? await logger.nutrition.lookup(request) {
            return usda
        }
        if let off = (try? await openFoodFacts.lookup(request)) ?? nil {
            MatchDebugLog.shared.record(transcript: "Matched \"\(request.name)\" via Open Food Facts")
            return off
        }
        return nil
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
        notice = nil
    }

    /// Search passthrough for the card's inline USDA search pane.
    func searchFoods(query: String) async -> [USDAFood] {
        (try? await logger.nutrition.search(query: query)) ?? []
    }

    // MARK: - Save

    func saveAll() async {
        guard canSaveAll, let context, let session = review else { return }
        // No workKind here: the review screen stays up for the whole save, so
        // the AnalyzingView spinner (which reads workingText) never shows.
        isWorking = true
        defer { isWorking = false }
        let entries = session.items.compactMap { item in
            item.match.map { (request: item.request, match: $0) }
        }
        do {
            try logger.saveResolved(entries, rawText: session.rawText, on: logDate, in: context)
            review = nil
            notice = nil
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
