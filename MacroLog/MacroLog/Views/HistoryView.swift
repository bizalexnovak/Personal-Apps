import SwiftUI
import SwiftData
import Charts

/// History: a trends chart (each nutrient as % of its daily goal, per day) with
/// week/month ranges and range averages, above the list of logged days.
struct HistoryView: View {
    @Query(sort: \Meal.timestamp, order: .reverse) private var meals: [Meal]

    @AppStorage(TargetKeys.calories) private var calorieTarget = 2000.0
    @AppStorage(TargetKeys.protein) private var proteinTarget = 150.0
    @AppStorage(TargetKeys.carbs) private var carbTarget = 250.0
    @AppStorage(TargetKeys.fat) private var fatTarget = 70.0
    @AppStorage(TargetKeys.water) private var waterTarget = 64.0

    @State private var range: TrendRange = .week

    // MARK: Derived data

    private var startDate: Date {
        Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(range.days - 1) * 86_400))
    }

    private var daysInRange: [DayTotals] {
        let inRange = meals.filter { $0.timestamp >= startDate }
        let grouped = Dictionary(grouping: inRange) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped
            .map { date, dayMeals in
                DayTotals(
                    date: date,
                    calories: dayMeals.reduce(0) { $0 + $1.totalCalories },
                    protein: dayMeals.reduce(0) { $0 + $1.totalProtein },
                    carbs: dayMeals.reduce(0) { $0 + $1.totalCarbs },
                    fat: dayMeals.reduce(0) { $0 + $1.totalFat },
                    water: dayMeals.reduce(0) { $0 + $1.waterOunces }
                )
            }
            .sorted { $0.date < $1.date }
    }

    private func target(_ metric: Metric) -> Double {
        switch metric {
        case .calories: return calorieTarget
        case .protein: return proteinTarget
        case .carbs: return carbTarget
        case .fat: return fatTarget
        case .water: return waterTarget
        }
    }

    /// One (metric, day, percent-of-goal) point for the chart.
    private var chartPoints: [MetricPoint] {
        daysInRange.flatMap { day in
            Metric.allCases.map { metric in
                let t = target(metric)
                return MetricPoint(
                    metric: metric,
                    date: day.date,
                    percent: t > 0 ? day.value(metric) / t * 100 : 0
                )
            }
        }
    }

    private var loggedDayCount: Int { daysInRange.count }

    private func average(_ metric: Metric) -> Double {
        guard loggedDayCount > 0 else { return 0 }
        return daysInRange.reduce(0) { $0 + $1.value(metric) } / Double(loggedDayCount)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Range", selection: $range) {
                        ForEach(TrendRange.allCases) { r in Text(r.title).tag(r) }
                    }
                    .pickerStyle(.segmented)

                    if daysInRange.isEmpty {
                        ContentUnavailableView(
                            "No data in this range",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Log some meals and your trends will show here.")
                        )
                    } else {
                        trendChart
                        averagesGrid
                    }
                } header: {
                    Text("Trends")
                } footer: {
                    if !daysInRange.isEmpty {
                        Text("Each line is that nutrient as a percent of your daily goal. The dashed line is 100% (goal).")
                    }
                }

                if !daysInRange.isEmpty {
                    Section(range == .week ? "Last 7 days" : "Last 30 days") {
                        ForEach(daysInRange.sorted { $0.date > $1.date }) { day in
                            NavigationLink {
                                DayDetailView(date: day.date, meals: mealsOn(day.date))
                            } label: {
                                DayRow(date: day.date, totals: day)
                            }
                        }
                    }
                }

                if meals.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "calendar",
                        description: Text("Days you log meals will show up here.")
                    )
                }
            }
            .navigationTitle("History")
        }
    }

    private func mealsOn(_ date: Date) -> [Meal] {
        meals.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) }
    }

    // MARK: Chart

    private var trendChart: some View {
        Chart {
            RuleMark(y: .value("Goal", 100))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("goal").font(.caption2).foregroundStyle(.secondary)
                }
            ForEach(chartPoints) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("% of goal", point.percent)
                )
                .foregroundStyle(by: .value("Nutrient", point.metric.title))
                .symbol(by: .value("Nutrient", point.metric.title))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartForegroundStyleScale(domain: Metric.allCases.map(\.title), range: Metric.allCases.map(\.color))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v))%") }
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 8)
        .frame(height: 240)
        .padding(.vertical, 4)
    }

    // MARK: Averages

    private var averagesGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(range == .week ? "Weekly average" : "Monthly average")
                .font(.subheadline.weight(.semibold))
            Text("over \(loggedDayCount) logged day\(loggedDayCount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { averageChips }
                VStack(alignment: .leading, spacing: 6) { averageChips }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var averageChips: some View {
        ForEach(Metric.allCases) { metric in
            HStack(spacing: 5) {
                Circle().fill(metric.color).frame(width: 8, height: 8)
                Text("\(Int(average(metric).rounded())) \(metric.unit)")
                    .font(.caption.monospacedDigit())
            }
        }
    }
}

// MARK: - Supporting types

enum TrendRange: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    var title: String { self == .week ? "Week" : "Month" }
    var days: Int { self == .week ? 7 : 30 }
}

enum Metric: String, CaseIterable, Identifiable {
    case calories, protein, carbs, fat, water
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calories: return "Calories"
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        case .water: return "Water"
        }
    }
    var unit: String {
        switch self {
        case .calories: return "kcal"
        case .water: return "oz"
        default: return "g"
        }
    }
    /// Chart-tuned shades of the app's macro colors — deeper than the Home
    /// rings so thin lines stay visible on a light surface (CVD-validated).
    var color: Color {
        switch self {
        case .calories: return Color(.sRGB, red: 0.961, green: 0.486, blue: 0.0)   // orange
        case .protein:  return Color(.sRGB, red: 0.898, green: 0.224, blue: 0.208) // red
        case .carbs:    return Color(.sRGB, red: 0.118, green: 0.533, blue: 0.898) // blue
        case .fat:      return Color(.sRGB, red: 0.722, green: 0.576, blue: 0.039) // gold
        case .water:    return Color(.sRGB, red: 0.0, green: 0.627, blue: 0.690)   // teal
        }
    }
}

struct DayTotals: Identifiable {
    var date: Date
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var water: Double
    var id: Date { date }

    func value(_ metric: Metric) -> Double {
        switch metric {
        case .calories: return calories
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        case .water: return water
        }
    }
}

struct MetricPoint: Identifiable {
    let id = UUID()
    var metric: Metric
    var date: Date
    var percent: Double
}

// MARK: - Day list rows

private struct DayRow: View {
    let date: Date
    let totals: DayTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)
            HStack(spacing: 10) {
                Text("\(Int(totals.calories.rounded())) kcal")
                Text("P \(Int(totals.protein.rounded()))")
                Text("C \(Int(totals.carbs.rounded()))")
                Text("F \(Int(totals.fat.rounded()))")
                Label("\(Int(totals.water.rounded())) oz", systemImage: "drop.fill")
                    .foregroundStyle(.cyan)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// One day's meals with a totals header. Meals are editable and deletable,
/// same as Today's list.
private struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let date: Date
    let meals: [Meal]

    private var sortedMeals: [Meal] {
        meals.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        List {
            Section("Totals") {
                totalRow("Calories", meals.reduce(0) { $0 + $1.totalCalories }, "kcal")
                totalRow("Protein", meals.reduce(0) { $0 + $1.totalProtein }, "g")
                totalRow("Carbs", meals.reduce(0) { $0 + $1.totalCarbs }, "g")
                totalRow("Fat", meals.reduce(0) { $0 + $1.totalFat }, "g")
                totalRow("Water", meals.reduce(0) { $0 + $1.waterOunces }, "oz")
            }
            Section("Meals") {
                ForEach(sortedMeals) { meal in
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
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(sortedMeals[index])
                    }
                }
            }
        }
        .navigationTitle(Text(date, format: .dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func totalRow(_ label: String, _ value: Double, _ unit: String) -> some View {
        LabeledContent(label) {
            Text("\(Int(value.rounded())) \(unit)")
                .monospacedDigit()
        }
    }
}
