import SwiftUI
import SwiftData

/// Which per-item sheet to present, hoisted to `EditMealView` so it lives on a
/// stable view (presenting from inside the ForEach row flash-dismisses because
/// SwiftData re-emitting the items recreates the row and its state).
struct EditorSheet: Identifiable {
    enum Kind: String { case macros = "m", swap = "s", micros = "n" }
    let item: FoodItem
    let kind: Kind
    var id: String { "\(item.persistentModelID.hashValue)-\(kind.rawValue)" }
}

struct EditMealView: View {
    @Bindable var meal: Meal
    @Environment(\.modelContext) private var modelContext
    @State private var sheet: EditorSheet?
    @State private var justDuplicated = false
    @State private var justSavedRecipe = false

    var body: some View {
        List {
            Section {
                // Capped at now: the Today diary can't navigate into the
                // future, so a future-dated meal would become unreachable.
                DatePicker(
                    "Logged",
                    selection: $meal.timestamp,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
            } header: {
                Text("Date & time")
            }

            Section {
                Text(meal.rawText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Original description")
            }

            ForEach(meal.items) { item in
                FoodItemEditor(item: item) { kind in
                    sheet = EditorSheet(item: item, kind: kind)
                }
            }

            Section {
                Button {
                    duplicateToToday()
                } label: {
                    Label(
                        justDuplicated ? "Added to today" : "Log this meal again today",
                        systemImage: justDuplicated ? "checkmark.circle.fill" : "plus.square.on.square"
                    )
                }
                .disabled(justDuplicated)

                Button {
                    saveAsRecipe()
                } label: {
                    Label(
                        justSavedRecipe ? "Saved to Recipes" : "Save as recipe",
                        systemImage: justSavedRecipe ? "checkmark.circle.fill" : "book.closed"
                    )
                }
                .disabled(justSavedRecipe)
            } footer: {
                Text("\u{201C}Log again\u{201D} adds a copy of this meal to today's diary. \u{201C}Save as recipe\u{201D} keeps it on the Recipes tab for one-tap re-logging anytime.")
            }
        }
        .keyboardDismissBar()
        .navigationTitle("Edit Meal")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { target in
            switch target.kind {
            case .macros:
                MacroOverrideSheet(item: target.item)
            case .swap:
                FoodSwapView(item: target.item)
            case .micros:
                MicroOverrideSheet(item: target.item)
            }
        }
    }

    /// Inserts a fresh copy of this meal (items, macros, micros) timestamped
    /// now, so a repeated meal can be re-logged without re-capturing it.
    private func duplicateToToday() {
        let copies = meal.items.map { item in
            let copy = FoodItem(
                name: item.name, quantity: item.quantity, unit: item.unit,
                calories: item.calories, protein: item.protein,
                carbs: item.carbs, fat: item.fat,
                matchConfidence: item.matchConfidence
            )
            copy.microsData = item.microsData
            return copy
        }
        let duplicate = Meal(timestamp: .now, rawText: meal.rawText, items: copies)
        modelContext.insert(duplicate)
        try? modelContext.save()
        justDuplicated = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justDuplicated = false
        }
    }

    /// Snapshots this meal as a reusable recipe on the Recipes tab.
    private func saveAsRecipe() {
        modelContext.insert(Recipe.from(meal: meal, named: meal.displayName))
        try? modelContext.save()
        justSavedRecipe = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justSavedRecipe = false
        }
    }
}

/// Editor for one food item: change quantity (macros rescale proportionally),
/// swap the matched USDA food, or tap the macro line to override values by hand.
private struct FoodItemEditor: View {
    @Bindable var item: FoodItem
    /// Ask the parent (EditMealView) to present a sheet for this item.
    var present: (EditorSheet.Kind) -> Void

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
            // A zero quantity is never meaningful (and would strand the item's
            // macros at their old values) — ignore attempts to reach it, e.g.
            // stepping "−" from 1, so the value stays where it was.
            guard newValue > 0 else { return }
            let old = item.quantity
            if old > 0 {
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

            // Quantity has +/- steppers for quick count changes (e.g. bumping
            // "6 strips of bacon" to 7) while still allowing tap-to-type. The
            // macros rescale with the count; they aren't stepped directly.
            Stepper(value: quantityBinding, in: 0...9999, step: 1) {
                HStack {
                    TextField("Quantity", value: quantityBinding, format: .number)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 70)
                        .textFieldStyle(.roundedBorder)
                    TextField("Unit", text: $item.unit)
                        .textFieldStyle(.roundedBorder)
                }
            }

            PortionSliderView(factor: Binding(
                get: { scaleFactor },
                set: { applyFactor($0) }
            ))

            Button {
                present(.macros)
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
                present(.swap)
            }
            .font(.subheadline)

            Button("Edit micronutrients & caffeine…") {
                present(.micros)
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
        // Re-anchor the portion slider's 1× when macros change from outside the
        // slider (macro override / food swap). Guarded to skip the slider's own
        // writes (which leave scaleFactor != 1) so it never fights a drag.
        .onChange(of: item.calories) { _, _ in
            if scaleFactor == 1 { reanchor() }
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
            .keyboardDismissBar()
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
            .keyboardDismissBar()
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

/// Meal-editor adapter: edits a saved FoodItem's micros via the shared
/// value-based editor.
private struct MicroOverrideSheet: View {
    @Bindable var item: FoodItem

    var body: some View {
        MicronutrientEditSheet(
            initial: item.micros,
            contextLine: "Per \(item.quantity.formatted()) \(item.unit) of \(item.name)"
        ) { item.micros = $0 }
    }
}

/// Editor for every micronutrient on one set of values — vitamins, minerals,
/// caffeine, creatine, pre-workout compounds. Fields are optional: an empty
/// box means "not recorded" (distinct from 0), matching how the values are
/// stored. Driven by the same `Micronutrients.fields` table as capture and
/// display, so a nutrient added there is automatically editable here.
/// Value-in/value-out so the meal editor (saved items) and the capture review
/// cards (pre-save matches) share one editor.
struct MicronutrientEditSheet: View {
    let initial: Micronutrients
    let contextLine: String
    let onSave: (Micronutrients) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var values: [Double?] = Array(
        repeating: nil, count: Micronutrients.fields.count
    )

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Array(Micronutrients.fields.enumerated()), id: \.offset) { index, field in
                        LabeledContent("\(field.label) (\(field.unit))") {
                            TextField("—", value: $values[index], format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 110)
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text(contextLine)
                } footer: {
                    Text("Leave a field empty for \u{201C}not recorded\u{201D} — that's different from 0.")
                }
            }
            .keyboardDismissBar()
            .navigationTitle("Micronutrients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var micros = Micronutrients()
                        for (index, field) in Micronutrients.fields.enumerated() {
                            micros[keyPath: field.keyPath] = values[index]
                        }
                        onSave(micros)
                        dismiss()
                    }
                }
            }
            .onAppear {
                values = Micronutrients.fields.map { initial[keyPath: $0.keyPath] }
            }
        }
    }
}

/// Read-only read-out of recorded micronutrients (fat/carb breakdown, minerals,
/// vitamins, caffeine…). Collapsed by default — this detail is captured with
/// each entry but intentionally kept out of the way. Shared between the meal
/// editor (one item), the Today tab (the whole day's totals), and the capture
/// review cards. The label carries a count so a collapsed row still says
/// whether there's anything inside; pass `onEdit` to append an edit button to
/// the expanded content (the review cards do).
struct MicronutrientDisclosure: View {
    let micros: Micronutrients
    var onEdit: (() -> Void)? = nil

    var body: some View {
        let recorded = micros.recorded
        DisclosureGroup(recorded.isEmpty ? "Micronutrients" : "Micronutrients (\(recorded.count))") {
            if recorded.isEmpty {
                Text("None recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label(
                        recorded.isEmpty ? "Add micronutrients…" : "Edit micronutrients…",
                        systemImage: "pencil"
                    )
                    .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
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
