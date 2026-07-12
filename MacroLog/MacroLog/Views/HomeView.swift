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

    private var dayMeals: [Meal] {
        meals.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: selectedDate) }
    }

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    /// Today's totals + targets for the home-screen widget (always today, not
    /// the browsed day).
    private var todaySnapshot: DayNutritionSnapshot {
        let cal = Calendar.current
        let todays = meals.filter { cal.isDateInToday($0.timestamp) }
        return DayNutritionSnapshot(
            date: cal.startOfDay(for: .now),
            calories: todays.reduce(0) { $0 + $1.totalCalories },
            protein: todays.reduce(0) { $0 + $1.totalProtein },
            carbs: todays.reduce(0) { $0 + $1.totalCarbs },
            fat: todays.reduce(0) { $0 + $1.totalFat },
            water: todays.reduce(0) { $0 + $1.waterOunces },
            calorieTarget: calorieTarget, proteinTarget: proteinTarget,
            carbTarget: carbTarget, fatTarget: fatTarget, waterTarget: waterTarget
        )
    }

    private func refreshWidget() {
        WidgetDataStore.write(todaySnapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var sortedDayMeals: [Meal] {
        dayMeals.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: Totals

    private var calories: Double { dayMeals.reduce(0) { $0 + $1.totalCalories } }
    private var protein: Double { dayMeals.reduce(0) { $0 + $1.totalProtein } }
    private var carbs: Double { dayMeals.reduce(0) { $0 + $1.totalCarbs } }
    private var fat: Double { dayMeals.reduce(0) { $0 + $1.totalFat } }
    private var water: Double { dayMeals.reduce(0) { $0 + $1.waterOunces } }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MacroProgressRow(
                        label: "Calories", unit: "kcal", color: palette.calories,
                        value: calories, target: calorieTarget
                    )
                    HStack(alignment: .top, spacing: 8) {
                        MacroRing(label: "Protein", unit: "g", color: palette.protein,
                                  value: protein, target: proteinTarget)
                        MacroRing(label: "Carbs", unit: "g", color: palette.carbs,
                                  value: carbs, target: carbTarget)
                        MacroRing(label: "Fat", unit: "g", color: palette.fat,
                                  value: fat, target: fatTarget)
                        MacroRing(label: "Water", unit: "oz", color: palette.water,
                                  value: water, target: waterTarget)
                    }
                    .padding(.vertical, 4)
                }

                if dayMeals.isEmpty {
                    ContentUnavailableView(
                        isToday ? "Nothing logged today" : "Nothing logged this day",
                        systemImage: "fork.knife",
                        description: Text(isToday
                            ? "Say \u{201C}Log meal in MacroLog\u{201D} to Siri, or add a meal from the Meals tab."
                            : "No meals were logged on this day.")
                    )
                } else {
                    Section {
                        hourlyChart
                    } header: {
                        Text("When you ate")
                    } footer: {
                        Text("Calories by the hour you logged them.")
                    }

                    Section("Meals") {
                        ForEach(sortedDayMeals) { meal in
                            NavigationLink {
                                EditMealView(meal: meal)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meal.displayName)
                                        .lineLimit(2)
                                    Text("\(Int(meal.totalCalories.rounded())) kcal · \(meal.timestamp, format: .dateTime.hour().minute())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: deleteMeals)
                    }
                }
            }
            .appBackground(appBackground)
            .onAppear { refreshWidget() }
            .onChange(of: todaySnapshot) { _, _ in refreshWidget() }
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

    private func deleteMeals(_ offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sortedDayMeals[index])
        }
    }

    // MARK: Hourly chart

    /// Calories binned to the hour they were logged.
    private var hourlyCalories: [HourBin] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: selectedDate)
        let grouped = Dictionary(grouping: dayMeals) { cal.component(.hour, from: $0.timestamp) }
        return grouped.map { hour, hourMeals in
            HourBin(
                time: cal.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay,
                calories: hourMeals.reduce(0) { $0 + $1.totalCalories }
            )
        }
        .sorted { $0.time < $1.time }
    }

    private var hourlyChart: some View {
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        let endOfDay = startOfDay.addingTimeInterval(24 * 3600)
        return Chart(hourlyCalories) { bin in
            BarMark(
                x: .value("Time", bin.time, unit: .hour),
                y: .value("Calories", bin.calories)
            )
            .foregroundStyle(palette.calories)
            .cornerRadius(3)
        }
        .chartXScale(domain: startOfDay ... endOfDay)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
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

/// Calories logged in one clock hour, for the intake timeline chart.
struct HourBin: Identifiable {
    var time: Date
    var calories: Double
    var id: Date { time }
}
