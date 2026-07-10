import SwiftUI
import SwiftData
import Charts

/// Trends: each nutrient as a percent of its daily goal over time, with
/// week/month/…/all ranges, per-range averages, and a tappable show/hide
/// legend. Per-day meals live on the Today tab (which navigates by day).
struct HistoryView: View {
    @Query(sort: \Meal.timestamp, order: .reverse) private var meals: [Meal]

    @AppStorage(TargetKeys.calories) private var calorieTarget = 2000.0
    @AppStorage(TargetKeys.protein) private var proteinTarget = 150.0
    @AppStorage(TargetKeys.carbs) private var carbTarget = 250.0
    @AppStorage(TargetKeys.fat) private var fatTarget = 70.0
    @AppStorage(TargetKeys.water) private var waterTarget = 64.0

    @State private var range: TrendRange = .week
    @State private var selectedMetrics: Set<Metric> = Set(Metric.allCases)

    /// Metrics currently shown, in the canonical order.
    private var visibleMetrics: [Metric] {
        Metric.allCases.filter { selectedMetrics.contains($0) }
    }

    // MARK: Derived data

    private var daysInRange: [DayTotals] {
        let inRange: [Meal]
        if let days = range.days {
            let start = Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86_400))
            inRange = meals.filter { $0.timestamp >= start }
        } else {
            inRange = meals
        }
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

    private func bucketStart(_ date: Date) -> Date {
        let cal = Calendar.current
        if range.bucket == .day { return cal.startOfDay(for: date) }
        return cal.dateInterval(of: range.bucket, for: date)?.start ?? cal.startOfDay(for: date)
    }

    /// One (metric, bucket, percent-of-goal) point. For ranges longer than a
    /// month, days are averaged into weekly/monthly buckets so the line stays
    /// readable — the percent is the average day in that bucket vs. its goal.
    private var chartPoints: [MetricPoint] {
        let buckets = Dictionary(grouping: daysInRange) { bucketStart($0.date) }
        return buckets.flatMap { start, days -> [MetricPoint] in
            visibleMetrics.map { metric in
                let avg = days.reduce(0) { $0 + $1.value(metric) } / Double(days.count)
                let t = target(metric)
                return MetricPoint(metric: metric, date: start, percent: t > 0 ? avg / t * 100 : 0)
            }
        }
        .sorted { $0.date < $1.date }
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
                        if visibleMetrics.isEmpty {
                            ContentUnavailableView(
                                "No nutrients selected",
                                systemImage: "chart.xyaxis.line",
                                description: Text("Tap a nutrient below to show it.")
                            )
                            .frame(height: 240)
                        } else {
                            trendChart
                        }
                        metricSelector
                    }
                } header: {
                    Text("Trends")
                } footer: {
                    if !daysInRange.isEmpty {
                        Text("Each line is that nutrient as a percent of your daily goal (dashed line = 100%). Tap a nutrient to show or hide it; the number is its average per day. Tap a day on the Today tab to see and edit its meals.")
                    }
                }
            }
            .navigationTitle("Trends")
        }
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
        .chartForegroundStyleScale(domain: visibleMetrics.map(\.title), range: visibleMetrics.map(\.color))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v))%") }
                }
            }
        }
        .chartLegend(.hidden)   // the tappable selector below is the legend
        .frame(height: 240)
        .padding(.vertical, 4)
    }

    // MARK: Metric selector (also the legend + averages)

    private var metricSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Average per day · \(range.averageCaption) · \(loggedDayCount) logged day\(loggedDayCount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(Metric.allCases) { metric in
                    metricChip(metric)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func metricChip(_ metric: Metric) -> some View {
        let on = selectedMetrics.contains(metric)
        return Button {
            if on { selectedMetrics.remove(metric) } else { selectedMetrics.insert(metric) }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(metric.color)
                    .frame(width: 9, height: 9)
                    .opacity(on ? 1 : 0.35)
                VStack(alignment: .leading, spacing: 0) {
                    Text(metric.title)
                        .font(.caption2)
                        .foregroundStyle(on ? .primary : .secondary)
                    Text("\(Int(average(metric).rounded())) \(metric.unit)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(on ? .primary : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(on ? metric.color.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(on ? metric.color.opacity(0.4) : Color.secondary.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Supporting types

enum TrendRange: String, CaseIterable, Identifiable {
    case week, month, threeMonths, sixMonths, year, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "1W"
        case .month: return "1M"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .year: return "1Y"
        case .all: return "All"
        }
    }

    /// Number of days back, or nil for all-time.
    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .year: return 365
        case .all: return nil
        }
    }

    /// How chart points are bucketed so long spans stay legible: daily for
    /// short ranges, weekly for a few months, monthly for a year+.
    var bucket: Calendar.Component {
        switch self {
        case .week, .month: return .day
        case .threeMonths, .sixMonths: return .weekOfYear
        case .year, .all: return .month
        }
    }

    var averageCaption: String {
        switch self {
        case .week: return "past week"
        case .month: return "past month"
        case .threeMonths: return "past 3 months"
        case .sixMonths: return "past 6 months"
        case .year: return "past year"
        case .all: return "all time"
        }
    }
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
    var metric: Metric
    var date: Date
    var percent: Double
    // Stable identity (metric + bucket date) so the chart doesn't rebuild and
    // re-animate every time the view body re-evaluates.
    var id: String { "\(metric.rawValue)-\(date.timeIntervalSince1970)" }
}

