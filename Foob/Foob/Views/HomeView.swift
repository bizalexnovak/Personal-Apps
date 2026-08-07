import SwiftUI
import SwiftData
import Charts
import WidgetKit

/// The day diary: navigate day by day, see calories against goal plus protein/
/// carbs/fat/water rings, an hourly intake chart, and that day's meals (which
/// are editable and deletable, same as anywhere else).
struct HomeView: View {
    @Query(sort: \Meal.timestamp, order: .reverse) private var meals: [Meal]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.metricPalette) private var palette
    @Environment(\.appBackground) private var appBackground

    @AppStorage(TargetKeys.calories) private var calorieTarget = 2000.0
    @AppStorage(TargetKeys.protein) private var proteinTarget = 150.0
    @AppStorage(TargetKeys.carbs) private var carbTarget = 250.0
    @AppStorage(TargetKeys.fat) private var fatTarget = 70.0
    @AppStorage(TargetKeys.water) private var waterTarget = 64.0

    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var showDatePicker = false

    /// Macros/Micros switch for the day tally at the top of the diary.
    private enum TallyScope { case macros, micros }
    @State private var tallyScope: TallyScope = .macros
    /// Micronutrient row tapped in the Micros tally → its info sheet.
    @State private var microInfoField: MicronutrientField?

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    /// Everything the diary shows for the selected day — totals, the meals
    /// (newest first), and the hourly chart bins — gathered in ONE pass over
    /// the query results. Computed once per body evaluation; the previous
    /// per-metric computed properties each re-filtered the whole history,
    /// costing ~8 full scans per render.
    private struct DayAggregate {
        var meals: [Meal] = []
        var calories = 0.0
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
        var water = 0.0
        var micros = Micronutrients.empty
        var bins: [IntakeBin] = []
    }

    private var dayAggregate: DayAggregate {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: selectedDate)
        var agg = DayAggregate()
        var hourFood: [Int: Double] = [:]
        var hourWater: [Int: Double] = [:]
        // The query is newest-first, so appending preserves that order. One
        // pass over each meal's items covers totals, micros, and hour bins.
        for meal in meals where cal.isDate(meal.timestamp, inSameDayAs: selectedDate) {
            agg.meals.append(meal)
            var mealCalories = 0.0
            var mealWater = 0.0
            for item in meal.itemList {
                mealCalories += item.calories
                mealWater += WaterConversion.ounces(for: item)
                agg.protein += item.protein
                agg.carbs += item.carbs
                agg.fat += item.fat
                // Only items with stored data pay the JSON decode.
                if item.microsData != nil {
                    agg.micros = agg.micros.adding(item.micros)
                }
            }
            agg.calories += mealCalories
            agg.water += mealWater
            let hour = cal.component(.hour, from: meal.timestamp)
            if mealCalories > 0 { hourFood[hour, default: 0] += mealCalories }
            if mealWater > 0 { hourWater[hour, default: 0] += mealWater }
        }
        // Bars are normalized to the daily goal so food and water share one
        // axis; a cleared/zero goal falls back to the default target instead
        // of hiding the series (the old chart always drew logged intake).
        let calDenominator = calorieTarget > 0 ? calorieTarget : 2000
        let waterDenominator = waterTarget > 0 ? waterTarget : 64
        var bins: [IntakeBin] = []
        for (hour, kcal) in hourFood {
            let time = cal.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
            bins.append(IntakeBin(time: time, series: .food, amount: kcal / calDenominator))
        }
        for (hour, oz) in hourWater {
            let time = cal.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
            bins.append(IntakeBin(time: time, series: .water, amount: oz / waterDenominator))
        }
        agg.bins = bins.sorted { $0.time < $1.time }
        return agg
    }

    /// Today's totals + targets for the home-screen widget (always today, not
    /// the browsed day). When the diary is showing today, the already-computed
    /// aggregate is reused instead of re-scanning the whole history.
    private func todaySnapshot(reusing day: DayAggregate?) -> DayNutritionSnapshot {
        let cal = Calendar.current
        var t = MealTotals()
        if let day {
            t.calories = day.calories
            t.protein = day.protein
            t.carbs = day.carbs
            t.fat = day.fat
            t.waterOunces = day.water
        } else {
            for meal in meals where cal.isDateInToday(meal.timestamp) {
                let m = meal.totals
                t.calories += m.calories
                t.protein += m.protein
                t.carbs += m.carbs
                t.fat += m.fat
                t.waterOunces += m.waterOunces
            }
        }
        return DayNutritionSnapshot(
            date: cal.startOfDay(for: .now),
            calories: t.calories, protein: t.protein, carbs: t.carbs, fat: t.fat,
            water: t.waterOunces,
            calorieTarget: calorieTarget, proteinTarget: proteinTarget,
            carbTarget: carbTarget, fatTarget: fatTarget, waterTarget: waterTarget
        )
    }

    private func refreshWidget(_ snapshot: DayNutritionSnapshot) {
        WidgetDataStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        // The reminder is only queued for today when goals aren't met yet, so
        // re-evaluate it whenever the day's totals change.
        ReminderManager.refresh()
    }

    // MARK: Body

    var body: some View {
        let day = dayAggregate
        let snapshot = todaySnapshot(reusing: isToday ? day : nil)
        return NavigationStack {
            List {
                Section {
                    Picker("View", selection: $tallyScope) {
                        Text("Macros").tag(TallyScope.macros)
                        Text("Micros").tag(TallyScope.micros)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    switch tallyScope {
                    case .macros:
                        MacroProgressRow(
                            label: "Calories", unit: "kcal", color: palette.calories,
                            value: day.calories, target: calorieTarget
                        )
                        HStack(alignment: .top, spacing: 8) {
                            MacroRing(label: "Protein", unit: "g", color: palette.protein,
                                      value: day.protein, target: proteinTarget)
                            MacroRing(label: "Carbs", unit: "g", color: palette.carbs,
                                      value: day.carbs, target: carbTarget)
                            MacroRing(label: "Fat", unit: "g", color: palette.fat,
                                      value: day.fat, target: fatTarget)
                            MacroRing(label: "Water", unit: "oz", color: palette.water,
                                      value: day.water, target: waterTarget)
                        }
                        .padding(.vertical, 4)
                    case .micros:
                        // The day's summed vitamins/minerals/supplements
                        // against adult Daily Values; tap a row for what it
                        // does and overconsumption warnings.
                        MicroTallySection(micros: day.micros) { field in
                            microInfoField = field
                        }
                    }
                }

                if day.meals.isEmpty {
                    ContentUnavailableView(
                        isToday ? "Nothing logged today" : "Nothing logged this day",
                        systemImage: "fork.knife",
                        description: Text(isToday
                            ? "Say \u{201C}Log meal in Foob\u{201D} to Siri, or add a meal from the Meals tab."
                            : "No meals were logged on this day.")
                    )
                } else {
                    Section {
                        hourlyChart(bins: day.bins)
                    } header: {
                        Text("When you ate & drank")
                    } footer: {
                        Text("Each bar is that hour's share of your daily calorie or water goal.")
                    }

                    Section("Meals") {
                        ForEach(day.meals) { meal in
                            NavigationLink {
                                EditMealView(meal: meal)
                            } label: {
                                mealRow(meal)
                            }
                        }
                        .onDelete { deleteMeals($0, from: day.meals) }
                    }

                    // The day's full micronutrient tally lives in the Micros
                    // scope of the switch at the top of the screen.
                }
            }
            .appBackground(appBackground)
            .onAppear { refreshWidget(snapshot) }
            .onChange(of: snapshot) { _, newValue in refreshWidget(newValue) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { shiftDay(-1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous day")
                }
                ToolbarItem(placement: .principal) {
                    // Tap the date to pop open a calendar and jump anywhere.
                    Button {
                        showDatePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(smartDateTitle).font(.headline)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Choose date")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !isToday {
                        Button("Today") {
                            selectedDate = Calendar.current.startOfDay(for: .now)
                        }
                    }
                    Button { shiftDay(1) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(isToday)
                    .accessibilityLabel("Next day")
                }
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
            .sheet(item: $microInfoField) { field in
                MicronutrientInfoSheet(
                    field: field,
                    todayAmount: dayAggregate.micros[keyPath: field.keyPath] ?? 0
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var datePickerSheet: some View {
        DatePicker(
            "",
            selection: $selectedDate,
            in: ...Calendar.current.startOfDay(for: .now),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding(.horizontal)
        .onChange(of: selectedDate) { _, newValue in
            let normalized = Calendar.current.startOfDay(for: newValue)
            if normalized != selectedDate { selectedDate = normalized }
            showDatePicker = false // tapping a day jumps and closes
        }
        .presentationDetents([.height(420)])
    }

    // MARK: Day navigation

    private var smartDateTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) { return "Today" }
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Move by whole days, never past today.
    private func shiftDay(_ delta: Int) {
        let cal = Calendar.current
        guard let shifted = cal.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        let today = cal.startOfDay(for: .now)
        selectedDate = min(cal.startOfDay(for: shifted), today)
    }

    /// One diary row: name, calories + time, and the macro chips — all from a
    /// single pass over the meal's items.
    private func mealRow(_ meal: Meal) -> some View {
        let t = meal.totals
        return VStack(alignment: .leading, spacing: 3) {
            Text(meal.displayName)
                .lineLimit(2)
            Text("\(Int(t.calories.rounded())) kcal · \(meal.timestamp, format: .dateTime.hour().minute())")
                .font(.caption)
                .foregroundStyle(.secondary)
            macroChips(for: t)
        }
    }

    /// Per-meal macro totals as small colored chips (matching the app's metric
    /// palette). Water-only meals skip the all-zero P/C/F chips and just show
    /// the water amount.
    @ViewBuilder
    private func macroChips(for t: MealTotals) -> some View {
        let hasMacros = t.calories > 0 || t.protein > 0 || t.carbs > 0 || t.fat > 0
        HStack(spacing: 5) {
            if hasMacros || t.waterOunces == 0 {
                macroChip("P", t.protein, palette.protein)
                macroChip("C", t.carbs, palette.carbs)
                macroChip("F", t.fat, palette.fat)
            }
            if t.waterOunces > 0 {
                waterChip(t.waterOunces)
            }
        }
        .padding(.top, 1)
    }

    private func macroChip(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text("\(Int(value.rounded()))g")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    private func waterChip(_ ounces: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "drop.fill")
                .font(.system(size: 8))
                .foregroundStyle(palette.water)
            Text("\(Int(ounces.rounded())) oz")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(palette.water.opacity(0.12)))
    }

    private func deleteMeals(_ offsets: IndexSet, from dayMeals: [Meal]) {
        for index in offsets {
            modelContext.delete(dayMeals[index])
        }
    }

    // MARK: Hourly chart

    /// Food calories and water ounces per hour, each as a fraction of its own
    /// daily goal so the two series sit on one comparable axis — a big drink
    /// reads as tall as a big meal instead of a sliver next to the calorie
    /// bars. The bins are built in `dayAggregate`'s single pass.
    private func hourlyChart(bins: [IntakeBin]) -> some View {
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        let endOfDay = startOfDay.addingTimeInterval(24 * 3600)
        return Chart(bins) { bin in
            BarMark(
                x: .value("Time", bin.time, unit: .hour),
                y: .value("Share of goal", bin.amount)
            )
            .foregroundStyle(by: .value("Logged", bin.series.rawValue))
            .position(by: .value("Logged", bin.series.rawValue))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale([
            IntakeBin.Series.food.rawValue: palette.calories,
            IntakeBin.Series.water.rawValue: palette.water,
        ])
        .chartXScale(domain: startOfDay ... endOfDay)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(format: FloatingPointFormatStyle<Double>.Percent())
        }
        .frame(height: 170)
        .padding(.vertical, 4)
    }
}

/// Calories vs. goal as a labelled progress bar (kept for the headline metric).
private struct MacroProgressRow: View {
    let label: String
    let unit: String
    let color: Color
    let value: Double
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(target.rounded())) \(unit)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: target > 0 ? min(value / target, 1) : 0)
                .tint(color)
        }
        .padding(.vertical, 4)
    }
}

/// A macro shown as a circular progress ring: consumed in the centre, goal
/// underneath. Fills toward the daily target and caps at a full ring.
private struct MacroRing: View {
    let label: String
    let unit: String
    let color: Color
    let value: Double
    let target: Double

    private var progress: Double { target > 0 ? min(value / target, 1) : 0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value.rounded()))")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: 60, height: 60)
            .animation(.easeInOut(duration: 0.3), value: progress)

            VStack(spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("/ \(Int(target.rounded())) \(unit)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int(value.rounded())) of \(Int(target.rounded())) \(unit)")
    }
}

/// One series' contribution in a single clock hour, for the intake timeline
/// chart. `series` groups the bar (food vs. water); `amount` is that hour's
/// share of the series' daily goal (0…1+), so both plot on one axis.
struct IntakeBin: Identifiable {
    enum Series: String { case food = "Food", water = "Water" }
    var time: Date
    var series: Series
    var amount: Double
    var id: String { "\(time.timeIntervalSince1970)-\(series.rawValue)" }
}
