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

    // A single sheet driver — two separate `.sheet` modifiers on one view make
    // SwiftUI flash-dismiss the first presentation, so both go through one.
    private enum ActiveSheet: Identifiable {
        case swap, macros
        var id: Int { self == .swap ? 0 : 1 }
    }
    @State private var activeSheet: ActiveSheet?

    // Portion slider: absolute against a baseline (1× = the item as it was when
    // the editor opened / was last manually changed). Typing or dragging scales
    // from that baseline, so it never compounds.
    @State private var base: (quantity: Double, calories: Double, protein: Double, carbs: Double, fat: Double, micros: Micronutrients)?
    @State private var scaleFactor: Double = 1

    /// Re-anchor 1× to the item's current values (after a manual quantity/macro
    /// change or a food swap).
    private func reanchor() {
        base = (item.quantity, item.calories, item.protein, item.carbs, item.fat, item.micros)
        scaleFactor = 1
    }

    private func applyFactor(_ f: Double) {
        guard let base else { return }
        scaleFactor = f
        item.quantity = base.quantity * f
        item.calories = base.calories * f
        item.protein = base.protein * f
        item.carbs = base.carbs * f
        item.fat = base.fat * f
        item.micros = base.micros.scaled(by: f)
    }

    /// Rescales macros linearly when the quantity changes, then re-anchors the
    /// slider so 1× tracks the new quantity.
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
                item.micros = item.micros.scaled(by: factor)
            }
            item.quantity = newValue
            reanchor()
        }
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

            PortionSliderView(factor: Binding(
                get: { scaleFactor },
                set: { applyFactor($0) }
            ))

            Button {
                activeSheet = .macros
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
                activeSheet = .swap
            }
            .font(.subheadline)

            MicronutrientDisclosure(micros: item.micros)
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
        .onAppear { reanchor() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .swap:
                FoodSwapView(item: item, onApply: reanchor)
            case .macros:
                MacroOverrideSheet(item: item, onApply: reanchor)
            }
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
    var onApply: () -> Void = {}
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
        item.micros = match.micros
        onApply()
        dismiss()
    }
}

/// Manual macro entry — overrides whatever the lookup produced and marks the
/// item as verified (high confidence).
private struct MacroOverrideSheet: View {
    @Bindable var item: FoodItem
    var onApply: () -> Void = {}
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
                        onApply()
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

/// Read-only read-out of an item's recorded micronutrients (fat/carb breakdown,
/// minerals, vitamins). Collapsed by default — this detail is captured with each
/// entry but intentionally kept out of the way.
private struct MicronutrientDisclosure: View {
    let micros: Micronutrients

    var body: some View {
        DisclosureGroup("Micronutrients") {
            let recorded = micros.recorded
            if recorded.isEmpty {
                Text("None recorded for this item.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recorded, id: \.label) { entry in
                    LabeledContent(entry.label) {
                        Text(format(entry.value, unit: entry.unit))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
        .font(.subheadline)
    }

    /// One decimal for small gram amounts, whole numbers for mg/mcg.
    private func format(_ value: Double, unit: String) -> String {
        if unit == "g" {
            let rounded = (value * 10).rounded() / 10
            let text = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
            return "\(text) \(unit)"
        }
        return "\(Int(value.rounded())) \(unit)"
    }
}
