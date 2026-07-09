import SwiftUI

/// One reviewable food item: matched name, macros, and Confirm / Edit / Search
/// actions. Low-confidence items auto-open in Edit, unmatched ones in Search.
/// Rendered inline inside CaptureView after capture + matching complete.
struct ReviewItemCard: View {
    let item: MealCaptureCoordinator.ReviewItem
    @ObservedObject var coordinator: MealCaptureCoordinator

    private enum Pane {
        case none, edit, search
    }

    @State private var pane: Pane = .none
    @State private var didAutoOpen = false

    // Edit pane
    @State private var calories = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var waterOz = 0.0

    // Search pane
    @State private var query = ""
    @State private var results: [USDAFood] = []
    @State private var isSearching = false
    @State private var searched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let question = item.clarificationQuestion, !item.options.isEmpty, item.status == .needsReview {
                optionChips(question: question)
            }

            macrosRow

            actionsRow

            switch pane {
            case .none: EmptyView()
            case .edit: editPane
            case .search: searchPane
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.5)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1.5)
        )
        .onAppear(perform: autoOpenIfNeeded)
    }

    private var borderColor: Color {
        switch item.status {
        case .confirmed: return .green.opacity(0.6)
        case .edited: return .blue.opacity(0.6)
        case .needsReview: return item.needsAttention ? .yellow.opacity(0.8) : .clear
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                // Prominent title = the cleanly parsed name the user said, so a
                // wrong USDA match is obvious (parsed vs. matched visibly differ).
                Text(item.request.name)
                    .font(.subheadline.weight(.semibold))
                if let matched = item.match?.matchedDescription {
                    Text("Matched to: \(matched)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No match found")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("\(item.request.quantity.formatted()) \(item.request.unit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                coordinator.removeItem(item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove item")
        }
    }

    private var statusIcon: some View {
        Group {
            switch item.status {
            case .confirmed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .edited:
                Image(systemName: "pencil.circle.fill").foregroundStyle(.blue)
            case .needsReview:
                Image(systemName: item.needsAttention ? "exclamationmark.circle.fill" : "circle")
                    .foregroundStyle(item.needsAttention ? .yellow : .secondary)
            }
        }
        .font(.title3)
    }

    // MARK: Option chips (clarification interpretations)

    private func optionChips(question: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(item.options) { option in
                        Button {
                            Task { await coordinator.chooseOption(item.id, option: option) }
                        } label: {
                            Text(option.label)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(.orange.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Macros

    private var isWater: Bool { WaterConversion.isWater(item.request.name) }

    @ViewBuilder
    private var macrosRow: some View {
        if isWater {
            // Water is tracked in ounces, not macros.
            let oz = WaterConversion.ounces(quantity: item.request.quantity, unit: item.request.unit)
            HStack(spacing: 6) {
                Image(systemName: "drop.fill").foregroundStyle(.cyan)
                Text("\(Int(oz.rounded())) oz water")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
        } else {
            HStack(spacing: 16) {
                macroValue("kcal", item.match?.calories)
                macroValue("P", item.match?.protein)
                macroValue("C", item.match?.carbs)
                macroValue("F", item.match?.fat)
                Spacer()
                if item.match?.confidence == MatchConfidence.low {
                    Label("Check", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    private func macroValue(_ label: String, _ value: Double?) -> some View {
        VStack(spacing: 0) {
            Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.subheadline.monospacedDigit().weight(.medium))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button {
                coordinator.confirm(item.id)
                pane = .none
            } label: {
                Label("Confirm", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .disabled(item.match == nil || item.status == .confirmed)

            Button {
                syncEditFields()
                pane = pane == .edit ? .none : .edit
            } label: {
                Label("Edit", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if !isWater {
                Button {
                    pane = pane == .search ? .none : .search
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.caption)
        .controlSize(.small)
    }

    // MARK: Edit pane

    @ViewBuilder
    private var editPane: some View {
        if isWater {
            VStack(spacing: 8) {
                editField("Water (oz)", value: $waterOz)
                Button("Apply") {
                    coordinator.applyWaterEdit(item.id, ounces: waterOz)
                    pane = .none
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 4)
        } else {
            VStack(spacing: 8) {
                editField("Calories (kcal)", value: $calories)
                editField("Protein (g)", value: $protein)
                editField("Carbs (g)", value: $carbs)
                editField("Fat (g)", value: $fat)
                Button("Apply") {
                    coordinator.applyEdit(item.id, calories: calories, protein: protein, carbs: carbs, fat: fat)
                    pane = .none
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }

    private func editField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 100)
        }
    }

    // MARK: Search pane

    private var searchPane: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search USDA foods…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await runSearch() } }
                Button("Go") {
                    Task { await runSearch() }
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }

            if isSearching {
                ProgressView()
            } else if results.isEmpty, searched {
                Text("Nothing found — try fewer words, or use Edit to enter macros.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(results.prefix(6)) { food in
                        Button {
                            coordinator.applyPickedFood(item.id, food: food)
                            pane = .none
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(food.description)
                                    .font(.caption)
                                    .multilineTextAlignment(.leading)
                                Text("\(food.dataType ?? "") · \(Int(food.macrosPer100g.calories.rounded())) kcal / 100 g\(food.brandOwner.map { " · \($0)" } ?? "")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        defer {
            isSearching = false
            searched = true
        }
        results = await coordinator.searchFoods(query: trimmed)
    }

    // MARK: Defaults

    private func syncEditFields() {
        calories = item.match?.calories ?? 0
        protein = item.match?.protein ?? 0
        carbs = item.match?.carbs ?? 0
        fat = item.match?.fat ?? 0
        waterOz = WaterConversion.ounces(quantity: item.request.quantity, unit: item.request.unit)
    }

    /// Low-confidence and unmatched items open straight into Edit/Search.
    private func autoOpenIfNeeded() {
        guard !didAutoOpen else { return }
        didAutoOpen = true
        query = item.request.name
        syncEditFields()
        if item.match == nil {
            pane = .search
        } else if item.match?.confidence == MatchConfidence.low {
            syncEditFields()
            pane = .edit
        }
    }
}
