import SwiftUI

/// One reviewable food item: matched name, macros, and Confirm / Edit / Search
/// actions. Low-confidence items auto-open in Edit, unmatched ones in Search.
/// Rendered inline inside the review after capture + matching complete.
struct ReviewItemCard: View {
    let item: MealCaptureCoordinator.ReviewItem
    @ObservedObject var coordinator: MealCaptureCoordinator

    private enum Pane {
        case none, edit, search
    }

    @State private var pane: Pane = .none
    @State private var didAutoOpen = false
    @State private var showMicroEditor = false

    // Edit pane
    @State private var editedName = ""
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
        VStack(alignment: .leading, spacing: 12) {
            header

            if let question = item.clarificationQuestion, !item.options.isEmpty, item.status == .needsReview {
                optionChips(question: question)
            }

            macrosRow

            if !isWater, item.match != nil {
                scaleRow
                // Micronutrients ride the match through the whole flow — show
                // them before saving, and let label mistakes (or a match with
                // nothing recorded) be fixed right here instead of after save.
                MicronutrientDisclosure(micros: item.match?.micros ?? .empty) {
                    showMicroEditor = true
                }
            }

            actionsRow

            switch pane {
            case .none: EmptyView()
            case .edit: editPane
            case .search: searchPane
            }
        }
        .padding(13)
        .background(Lux.panel)
        .clipShape(RoundedRectangle(cornerRadius: Lux.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Lux.panelRadius)
                .stroke(borderColor, lineWidth: needsAttention ? 1.5 : 1)
        )
        .onAppear(perform: autoOpenIfNeeded)
        .sheet(isPresented: $showMicroEditor) {
            MicronutrientEditSheet(
                initial: item.match?.micros ?? .empty,
                contextLine: "Per \(item.request.quantity.formatted()) \(item.request.unit) of \(item.request.name)"
            ) { coordinator.applyMicrosEdit(item.id, micros: $0) }
            .luxSheetChrome()
        }
    }

    /// An item the parser or the match isn't sure about. The whole card takes
    /// the ember treatment rather than just its seal, so it reads as one thing
    /// wanting attention.
    private var needsAttention: Bool {
        item.match == nil
            || item.match?.confidence == MatchConfidence.low
            || (item.status == .needsReview && item.needsAttention)
    }

    private var borderColor: Color {
        needsAttention ? Lux.ember.opacity(0.6) : Lux.panelBorder
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            statusSeal
            VStack(alignment: .leading, spacing: 3) {
                // Prominent title = the cleanly parsed name the user said, so a
                // wrong USDA match is obvious (parsed vs. matched visibly differ).
                Text(item.request.name)
                    .font(Lux.serif(21, medium: true))
                    .foregroundStyle(Lux.cream)
                Text(matchLine)
                    .font(Lux.serifItalic(13))
                    .foregroundStyle(item.match == nil ? Lux.ember : Lux.cream.opacity(0.5))
            }
            Spacer(minLength: 8)
            Button {
                coordinator.removeItem(item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(Lux.cream.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove item")
        }
    }

    /// "Matched to Bar, granola — 1 bar." — what it was matched against and
    /// how much of it, in one line.
    private var matchLine: String {
        let portion = "\(item.request.quantity.formatted()) \(item.request.unit)"
        guard let matched = item.match?.matchedDescription else {
            return "No match found — \(portion)."
        }
        return "Matched to \(matched) — \(portion)."
    }

    private var statusSeal: some View {
        Group {
            switch item.status {
            case .confirmed:
                Circle()
                    .fill(Lux.goldFill)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Lux.ground))
            case .edited:
                Circle()
                    .fill(Lux.goldFill)
                    .overlay(
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Lux.ground))
            case .needsReview:
                if needsAttention {
                    Circle()
                        .stroke(Lux.ember, lineWidth: 1.5)
                        .overlay(
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Lux.ember))
                } else {
                    Circle().stroke(Lux.controlBorder, lineWidth: 1)
                }
            }
        }
        .frame(width: 26, height: 26)
    }

    // MARK: Option chips (clarification interpretations)

    private func optionChips(question: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(Lux.serifItalic(14))
                .foregroundStyle(Lux.cream.opacity(0.55))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(item.options) { option in
                        Button {
                            Task { await coordinator.chooseOption(item.id, option: option) }
                        } label: {
                            Text(option.label)
                                .font(Lux.serif(15))
                                .foregroundStyle(Lux.cream)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().stroke(Lux.ember.opacity(0.7), lineWidth: 1))
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
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(oz.rounded()))")
                    .font(Lux.serif(22))
                    .monospacedDigit()
                    .foregroundStyle(Lux.gold)
                Text("OZ WATER")
                    .font(Lux.smallcaps(7))
                    .tracking(1.5)
                    .foregroundStyle(Lux.cream.opacity(0.45))
                Spacer()
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                macroValue("KCAL", item.match?.calories)
                macroValue("PROTEIN", item.match?.protein)
                macroValue("CARBS", item.match?.carbs)
                macroValue("FAT", item.match?.fat)
                if item.match?.confidence == MatchConfidence.low {
                    VStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Lux.ember)
                        Text("CHECK")
                            .font(Lux.smallcaps(7))
                            .tracking(1.5)
                            .foregroundStyle(Lux.ember)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func macroValue(_ label: String, _ value: Double?) -> some View {
        VStack(spacing: 3) {
            Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                .font(Lux.serif(22))
                .monospacedDigit()
                .foregroundStyle(Lux.gold)
            Text(label)
                .font(Lux.smallcaps(7))
                .tracking(1.5)
                .foregroundStyle(Lux.cream.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Scale

    private var scaleRow: some View {
        PortionSliderView(factor: Binding(
            get: { item.scaleFactor },
            set: { coordinator.setScale(item.id, factor: $0) }
        ))
    }

    // MARK: Actions

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button {
                coordinator.confirm(item.id)
                pane = .none
            } label: {
                Text("CONFIRM").frame(maxWidth: .infinity)
            }
            .buttonStyle(GhostCapsule(gold: true, height: 36))
            .disabled(item.match == nil || item.status == .confirmed)
            .opacity(item.match == nil || item.status == .confirmed ? 0.4 : 1)

            Button {
                syncEditFields()
                pane = pane == .edit ? .none : .edit
            } label: {
                Text("EDIT").frame(maxWidth: .infinity)
            }
            .buttonStyle(GhostCapsule(height: 36))

            if !isWater {
                Button {
                    pane = pane == .search ? .none : .search
                } label: {
                    Text("SEARCH").frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostCapsule(height: 36))
            }
        }
    }

    // MARK: Edit pane

    @ViewBuilder
    private var editPane: some View {
        VStack(spacing: 0) {
            if isWater {
                editRow("WATER (OZ)", value: $waterOz)
                applyButton {
                    coordinator.applyWaterEdit(item.id, ounces: waterOz)
                }
            } else {
                HStack {
                    LuxFieldLabel(text: "NAME")
                    Spacer()
                    TextField("", text: $editedName)
                        .font(Lux.serif(17))
                        .foregroundStyle(Lux.cream)
                        .tint(Lux.gold)
                        .multilineTextAlignment(.trailing)
                }
                .luxRow(vertical: 9)

                editRow("CALORIES", value: $calories)
                editRow("PROTEIN (G)", value: $protein)
                editRow("CARBS (G)", value: $carbs)
                editRow("FAT (G)", value: $fat)
                applyButton {
                    coordinator.rename(item.id, to: editedName)
                    coordinator.applyEdit(item.id, calories: calories, protein: protein, carbs: carbs, fat: fat)
                }
            }
        }
        .padding(.top, 2)
    }

    private func editRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            LuxFieldLabel(text: label)
            Spacer()
            TextField("", value: value, format: .number)
                .keyboardType(.decimalPad)
                .font(Lux.serif(17))
                .monospacedDigit()
                .foregroundStyle(Lux.cream)
                .tint(Lux.gold)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
        }
        .luxRow(vertical: 9)
    }

    private func applyButton(_ action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button("APPLY") {
                action()
                pane = .none
            }
            .buttonStyle(GoldCapsule(height: 38))
            .frame(maxWidth: 130)
        }
        .padding(.top, 12)
    }

    // MARK: Search pane

    private var searchPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LuxUnderlinedField(
                    placeholder: "Search USDA foods…",
                    text: $query,
                    size: 17,
                    autocapitalization: .sentences
                )
                .onSubmit { Task { await runSearch() } }

                Button("GO") { Task { await runSearch() } }
                    .buttonStyle(GhostCapsule(gold: true, height: 34))
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }

            if isSearching {
                LuxNote("Searching…")
            } else if results.isEmpty, searched {
                LuxNote("Nothing found — try fewer words, or use Edit to enter macros.")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(results.prefix(6)) { food in
                        Button {
                            coordinator.applyPickedFood(item.id, food: food)
                            pane = .none
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.description)
                                    .font(Lux.serif(16))
                                    .foregroundStyle(Lux.cream)
                                    .multilineTextAlignment(.leading)
                                Text(resultSubtitle(food))
                                    .font(Lux.smallcaps(8))
                                    .tracking(1.5)
                                    .foregroundStyle(Lux.cream.opacity(0.45))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .luxRow(vertical: 9)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func resultSubtitle(_ food: USDAFood) -> String {
        let kind = (food.dataType ?? "").uppercased()
        let kcal = "\(Int(food.macrosPer100g.calories.rounded())) KCAL / 100 G"
        let brand = food.brandOwner.map { " · \($0.uppercased())" } ?? ""
        return kind.isEmpty ? "\(kcal)\(brand)" : "\(kind) · \(kcal)\(brand)"
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
        editedName = item.request.name
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
