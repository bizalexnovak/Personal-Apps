import SwiftUI

/// Fallback card when USDA search found nothing for an item: the user can
/// re-search the database with their own query, enter macros by hand, skip
/// the item, or cancel the meal. Nothing is saved until they decide.
struct ManualMatchSheet: View {
    let resolution: MealCaptureCoordinator.PendingResolution
    @ObservedObject var coordinator: MealCaptureCoordinator

    private enum Mode: Hashable {
        case search, manual
    }

    @State private var mode: Mode = .search
    @State private var query = ""
    @State private var results: [USDAFood] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searched = false

    @State private var calories = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0

    private let service = USDANutritionLookupService()

    private var item: FoodItemRequest { resolution.request }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't find an exact match for \u{201C}\(item.name)\u{201D}")
                        .font(.headline)
                    Text("Search the USDA database with different words, or enter the macros yourself.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                Picker("How do you want to resolve it?", selection: $mode) {
                    Text("Search USDA").tag(Mode.search)
                    Text("Enter macros").tag(Mode.manual)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch mode {
                case .search: searchMode
                case .manual: manualMode
                }

                Button("Skip this item") {
                    Task { await coordinator.skipUnmatchedItem() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            }
            .navigationTitle("No match found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel meal", role: .destructive) {
                        coordinator.cancelMeal()
                    }
                }
            }
            .onAppear {
                query = item.name
            }
        }
    }

    // MARK: - Manual USDA search

    private var searchMode: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search foods…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await runSearch() } }
                Button("Search") {
                    Task { await runSearch() }
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }
            .padding(.horizontal)

            if isSearching {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if let searchError {
                Text(searchError)
                    .foregroundStyle(.red)
                    .font(.subheadline)
                    .frame(maxHeight: .infinity)
            } else if results.isEmpty {
                Text(searched ? "Still nothing — try fewer or different words, or enter the macros manually." : "Try a simpler query, like just the brand or just the food.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxHeight: .infinity)
            } else {
                List(results) { food in
                    Button {
                        select(food)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.description)
                            HStack {
                                if let brand = food.brandOwner {
                                    Text(brand)
                                }
                                Text("\(Int(food.macrosPer100g.calories.rounded())) kcal / 100 g")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        defer {
            isSearching = false
            searched = true
        }
        do {
            searchError = nil
            results = try await service.search(query: trimmed)
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func select(_ food: USDAFood) {
        // The user picked this entry themselves, so name score is 1.0; the
        // grams resolution and plausibility checks still apply.
        let match = USDANutritionLookupService.match(for: item, food: food, nameScore: 1.0)
        Task { await coordinator.resolveManually(match) }
    }

    // MARK: - Manual macro entry

    private var manualMode: some View {
        Form {
            Section("Macros for \(item.quantity.formatted()) \(item.unit) of \(item.name)") {
                macroField("Calories (kcal)", value: $calories)
                macroField("Protein (g)", value: $protein)
                macroField("Carbs (g)", value: $carbs)
                macroField("Fat (g)", value: $fat)
            }
            Button("Save item") {
                let match = NutritionMatch(
                    matchedDescription: "Manual entry",
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    confidence: MatchConfidence.high // user-verified values
                )
                Task { await coordinator.resolveManually(match) }
            }
            .disabled(calories == 0 && protein == 0 && carbs == 0 && fat == 0)
        }
    }

    private func macroField(_ label: String, value: Binding<Double>) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }
}
