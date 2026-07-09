import SwiftUI
import SwiftData

struct EditMealView: View {
    @Bindable var meal: Meal

    var body: some View {
        List {
            Section {
                Text(meal.rawText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Original description")
            }

            ForEach(meal.items) { item in
                FoodItemEditor(item: item)
            }
        }
        .navigationTitle("Edit Meal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Editor for one food item: change quantity (macros rescale proportionally),
/// swap the matched USDA food, or tap the macro line to override values by hand.
private struct FoodItemEditor: View {
    @Bindable var item: FoodItem
    @State private var showSwapSheet = false
    @State private var showOverrideSheet = false

    /// Scale factors for the quick-adjust row (relative to current values).
    private static let scaleOptions: [(label: String, factor: Double)] = [
        ("½×", 0.5), ("⅔×", 2.0 / 3.0), ("1½×", 1.5), ("2×", 2), ("3×", 3),
    ]

    /// Rescales macros linearly when the quantity changes — valid because the
    /// stored macros were computed as (per-gram values × quantity).
    private var quantityBinding: Binding<Double> {
        Binding {
            item.quantity
        } set: { newValue in
            let old = item.quantity
            if old > 0, newValue > 0 {
                let factor = newValue / old
                item.calories *= factor
                item.protein *= factor
                item.carbs *= factor
                item.fat *= factor
            }
            item.quantity = newValue
        }
    }

    /// Scales quantity and every macro by the same factor — for repeat meals
    /// where you ate more or less than last time (½ a pepper, 2 scoops, …).
    private func scale(_ factor: Double) {
        item.quantity *= factor
        item.calories *= factor
        item.protein *= factor
        item.carbs *= factor
        item.fat *= factor
    }

    var body: some View {
        Section {
            TextField("Name", text: $item.name)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Quantity", value: quantityBinding, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 80)
                    .textFieldStyle(.roundedBorder)
                TextField("Unit", text: $item.unit)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 6) {
                Text("Scale")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Self.scaleOptions, id: \.label) { option in
                    Button(option.label) { scale(option.factor) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Button {
                showOverrideSheet = true
            } label: {
                HStack(spacing: 12) {
                    macroValue("kcal", item.calories)
                    macroValue("P", item.protein)
                    macroValue("C", item.carbs)
                    macroValue("F", item.fat)
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Button("Swap matched food…") {
                showSwapSheet = true
            }
            .font(.subheadline)
        } header: {
            HStack {
                Text(item.name.isEmpty ? "Item" : item.name)
                if item.matchConfidence == MatchConfidence.low {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Low confidence match")
                }
            }
        }
        .sheet(isPresented: $showSwapSheet) {
            FoodSwapView(item: item)
        }
        .sheet(isPresented: $showOverrideSheet) {
            MacroOverrideSheet(item: item)
        }
    }

    private func macroValue(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 0) {
            Text("\(Int(value.rounded()))")
                .font(.subheadline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// Search USDA FoodData Central and replace which food this item's macros
/// come from. Selecting a result recomputes macros for the item's current
/// quantity and unit.
private struct FoodSwapView: View {
    @Bindable var item: FoodItem
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [USDAFood] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let service = USDANutritionLookupService()

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(results) { food in
                    Button {
                        select(food)
                    } label: {
                        VStack(alignment: .leading) {
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
            }
            .searchable(text: $query, prompt: "Search foods")
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .overlay {
                if isSearching { ProgressView() }
            }
            .navigationTitle("Swap Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                query = item.name
                await search()
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            errorMessage = nil
            results = try await service.search(query: trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func select(_ food: USDAFood) {
        let request = FoodItemRequest(name: item.name, quantity: item.quantity, unit: item.unit)
        // nameScore 1.0: the user picked this match explicitly, so confidence
        // only stays low if the unit still required a guessed weight.
        let match = USDANutritionLookupService.match(for: request, food: food, nameScore: 1.0)
        item.calories = match.calories
        item.protein = match.protein
        item.carbs = match.carbs
        item.fat = match.fat
        item.matchConfidence = match.confidence
        dismiss()
    }
}

/// Manual macro entry — overrides whatever the lookup produced and marks the
/// item as verified (high confidence).
private struct MacroOverrideSheet: View {
    @Bindable var item: FoodItem
    @Environment(\.dismiss) private var dismiss

    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Macros for \(item.quantity.formatted()) \(item.unit) of \(item.name)") {
                    LabeledContent("Calories (kcal)") {
                        TextField("kcal", value: $calories, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Protein (g)") {
                        TextField("g", value: $protein, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Carbs (g)") {
                        TextField("g", value: $carbs, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Fat (g)") {
                        TextField("g", value: $fat, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Override Macros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        item.calories = calories
                        item.protein = protein
                        item.carbs = carbs
                        item.fat = fat
                        item.matchConfidence = MatchConfidence.high
                        dismiss()
                    }
                }
            }
            .onAppear {
                calories = item.calories
                protein = item.protein
                carbs = item.carbs
                fat = item.fat
            }
        }
    }
}
