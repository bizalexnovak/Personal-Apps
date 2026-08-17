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
    /// Meal row tapped → Edit Meal. Held by ID rather than by object so the
    /// destination survives the model refreshing underneath it.
    @State private var editingMealID: PersistentIdentifier?

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
            for item in meal.items {
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
            VStack(spacing: 0) {
                header(day: day)
                // Still a List, not a ScrollView: the rows keep swipe-to-delete
                // and the diary keeps its cell recycling. Every piece of its
                // chrome is stripped so the ruled-ledger look survives.
                List {
                    Group {
                        switch tallyScope {
                        case .macros: macrosContent(day: day)
                        case .micros: microsContent(day: day)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: Lux.hPad, bottom: 0, trailing: Lux.hPad))

                    Color.clear
                        .frame(height: OrbNavBar.clearance)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
            }
            .luxScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $editingMealID) { id in
                if let meal = meals.first(where: { $0.persistentModelID == id }) {
                    EditMealView(meal: meal)
                }
            }
            .onAppear { refreshWidget(snapshot) }
            .onChange(of: snapshot) { _, newValue in refreshWidget(newValue) }
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

    // MARK: Header

    private func header(day: DayAggregate) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { shiftDay(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Lux.cream)
                }
                .accessibilityLabel("Previous day")

                Spacer()

                // Forward a day is only meaningful in the past; on today the
                // calendar is the only way out, so it takes the slot alone.
                if !isToday {
                    Button { shiftDay(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Lux.cream)
                    }
                    .accessibilityLabel("Next day")
                    .padding(.trailing, 16)
                }

                Button { showDatePicker = true } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Lux.cream)
                }
                .accessibilityLabel("Choose date")
            }
            .padding(.bottom, 8)

            LuxTitle(text: smartDateTitle.uppercased())

            Text(subtitle(day: day))
                .font(Lux.serifItalic(15))
                .foregroundStyle(Lux.cream.opacity(0.55))
                .padding(.top, 6)

            LuxSwitcher(
                options: [(TallyScope.macros, "MACROS"), (TallyScope.micros, "MICROS")],
                selection: $tallyScope
            )
            .padding(.top, 12)
        }
        .padding(.horizontal, Lux.hPad)
        .padding(.top, 64)
    }

    /// "Sunday, 17 August · 1,365 kcal in." — the day and what it amounts to,
    /// in one line.
    private func subtitle(day: DayAggregate) -> String {
        let date = selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard day.calories > 0 else { return "\(date) · nothing logged yet." }
        return "\(date) · \(Self.grouped(day.calories)) kcal in."
    }

    private static func grouped(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    // MARK: Macros

    @ViewBuilder
    private func macrosContent(day: DayAggregate) -> some View {
        LuxSectionHeader(text: "CALORIES")
            .padding(.top, 14)
            .padding(.bottom, 2)

        HStack(alignment: .firstTextBaseline) {
            Text(Self.grouped(day.calories))
                .font(Lux.serif(38, medium: true))
                .monospacedDigit()
                .foregroundStyle(Lux.cream)
            Spacer()
            Text("of \(Self.grouped(calorieTarget)) kcal")
                .font(Lux.serifItalic(15))
                .foregroundStyle(Lux.cream.opacity(0.5))
        }

        LuxBar(progress: calorieTarget > 0 ? min(day.calories / calorieTarget, 1) : 0)
            .padding(.top, 6)

        HStack(spacing: 6) {
            LuxRing(label: "PROTEIN", unit: "g", metric: .protein,
                    value: day.protein, target: proteinTarget)
            LuxRing(label: "CARBS", unit: "g", metric: .carbs,
                    value: day.carbs, target: carbTarget)
            LuxRing(label: "FAT", unit: "g", metric: .fat,
                    value: day.fat, target: fatTarget)
            LuxRing(label: "WATER", unit: "oz", metric: .water,
                    value: day.water, target: waterTarget)
        }
        .padding(.top, 18)
        .padding(.bottom, 4)

        if day.meals.isEmpty {
            LuxNote(isToday
                    ? "Nothing logged today. Tap the bar below to describe a meal, or say “Log meal in Foob” to Siri."
                    : "No meals were logged on this day.",
                    size: 15)
                .padding(.top, 24)
        } else {
            LuxSectionHeader(text: "WHEN YOU ATE & DRANK")
                .padding(.top, 20)
                .padding(.bottom, 8)

            hourlyChart(bins: day.bins)

            LuxSectionHeader(text: "MEALS")
                .padding(.top, 20)
                .padding(.bottom, 2)

            // A Button rather than a NavigationLink: links in a List draw a
            // system disclosure chevron, and these rows end in a gold value.
            ForEach(day.meals) { meal in
                Button {
                    editingMealID = meal.persistentModelID
                } label: {
                    LuxMealRow(meal: meal)
                }
                .buttonStyle(.plain)
                .luxRow()
            }
            .onDelete { deleteMeals($0, from: day.meals) }
        }
    }

    @ViewBuilder
    private func microsContent(day: DayAggregate) -> some View {
        MicroTallySection(micros: day.micros) { field in
            microInfoField = field
        }
        .padding(.top, 8)

        LuxNote("Measured against adult Daily Values; nutrients without one show the tally alone.")
            .padding(.top, 12)
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

    private var datePickerSheet: some View {
        DatePicker(
            "",
            selection: $selectedDate,
            in: ...Calendar.current.startOfDay(for: .now),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .tint(Lux.gold)
        .labelsHidden()
        .padding(.horizontal)
        .onChange(of: selectedDate) { _, newValue in
            let normalized = Calendar.current.startOfDay(for: newValue)
            if normalized != selectedDate { selectedDate = normalized }
            showDatePicker = false // tapping a day jumps and closes
        }
        .presentationDetents([.height(420)])
        .presentationBackground(Lux.sheet)
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
        return VStack(spacing: 10) {
            Chart(bins) { bin in
                BarMark(
                    x: .value("Time", bin.time, unit: .hour),
                    y: .value("Share of goal", bin.amount)
                )
                .foregroundStyle(by: .value("Logged", bin.series.rawValue))
                .position(by: .value("Logged", bin.series.rawValue))
                .cornerRadius(1)
            }
            .chartForegroundStyleScale([
                IntakeBin.Series.food.rawValue: Lux.gold,
                IntakeBin.Series.water.rawValue: Lux.cream.opacity(0.55),
            ])
            .chartLegend(.hidden)
            .chartXScale(domain: startOfDay ... endOfDay)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine().foregroundStyle(Lux.cream.opacity(0.1))
                    AxisValueLabel(format: .dateTime.hour())
                        .font(Lux.smallcaps(9))
                        .foregroundStyle(Lux.cream.opacity(0.45))
                }
            }
            .chartYAxis {
                AxisMarks(format: FloatingPointFormatStyle<Double>.Percent()) { _ in
                    AxisGridLine().foregroundStyle(Lux.cream.opacity(0.1))
                    AxisValueLabel()
                        .font(Lux.smallcaps(9))
                        .foregroundStyle(Lux.cream.opacity(0.45))
                }
            }
            .frame(height: 150)

            // Square swatches rather than the default dots — the chart has no
            // rounded geometry anywhere else.
            HStack(spacing: 14) {
                legendSwatch("FOOD", Lux.gold)
                legendSwatch("WATER", Lux.cream.opacity(0.55))
                Spacer()
            }
        }
        .luxPanel()
    }

    private func legendSwatch(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(Lux.smallcaps(7.5))
                .tracking(1.5)
                .foregroundStyle(Lux.cream.opacity(0.45))
        }
    }
}

// MARK: - Meal ledger

/// One diary row: serif name, a smallcaps line of time and macros, and the
/// day's contribution right-aligned in gold.
struct LuxMealRow: View {
    let meal: Meal

    var body: some View {
        let t = meal.totals
        let waterOnly = t.calories == 0 && t.waterOunces > 0
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.displayName)
                    .font(Lux.serif(18, medium: true))
                    .foregroundStyle(Lux.cream)
                    .lineLimit(2)
                Text(subtitle(t, waterOnly: waterOnly))
                    .font(Lux.smallcaps(8))
                    .tracking(1.5)
                    .foregroundStyle(Lux.cream.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int((waterOnly ? t.waterOunces : t.calories).rounded()))")
                    .font(Lux.serif(22))
                    .monospacedDigit()
                    .foregroundStyle(Lux.gold)
                Text(waterOnly ? "OZ" : "KCAL")
                    .font(Lux.smallcaps(7))
                    .tracking(1.5)
                    .foregroundStyle(Lux.cream.opacity(0.45))
            }
        }
    }

    private func subtitle(_ t: MealTotals, waterOnly: Bool) -> String {
        let time = meal.timestamp.formatted(.dateTime.hour().minute())
        guard !waterOnly else { return time }
        return "\(time) · P \(Int(t.protein.rounded())) · C \(Int(t.carbs.rounded())) · F \(Int(t.fat.rounded()))"
    }
}

// MARK: - Gauges

/// A 3pt goal bar: cream track, gold gradient fill.
struct LuxBar: View {
    let progress: Double
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Lux.cream.opacity(0.08))
                Capsule()
                    .fill(Lux.goldFillH)
                    .frame(width: geo.size.width * max(0, min(progress, 1)))
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

/// A macro shown as a circular progress ring: consumed in the centre, goal
/// underneath. Fills toward the daily target and caps at a full ring. The
/// track is the ring's own colour at low alpha, so each ring reads as one
/// object rather than a coloured arc on shared grey.
struct LuxRing: View {
    let label: String
    let unit: String
    let metric: Metric
    let value: Double
    let target: Double

    private var progress: Double { target > 0 ? min(value / target, 1) : 0 }
    private var color: Color { metric.luxRingColor }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.16), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value.rounded()))")
                    .font(Lux.serif(20))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(6)
            }
            .padding(3)
            .frame(width: 62, height: 62)
            .animation(.easeInOut(duration: 0.3), value: progress)

            VStack(spacing: 2) {
                Text(label)
                    .font(Lux.smallcaps(7.5))
                    .tracking(1.8)
                    .foregroundStyle(Lux.cream.opacity(0.6))
                Text("/ \(Int(target.rounded())) \(unit)")
                    .font(Lux.smallcaps(7))
                    .tracking(1)
                    .monospacedDigit()
                    .foregroundStyle(Lux.cream.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label.capitalized): \(Int(value.rounded())) of \(Int(target.rounded())) \(unit)")
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
