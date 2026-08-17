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

    /// Per-day totals for the selected range, built in one pass over the
    /// history (one `meal.totals` per meal instead of five separate reduces).
    /// Computed ONCE per body evaluation and passed down — the chart, the day
    /// count, and every average chip previously each recomputed this whole
    /// aggregation, costing ~14 full-history scans per render.
    private var daysInRange: [DayTotals] {
        let cal = Calendar.current
        let start = range.days.map {
            cal.startOfDay(for: Date().addingTimeInterval(-Double($0 - 1) * 86_400))
        }
        var byDay: [Date: DayTotals] = [:]
        for meal in meals {
            if let start, meal.timestamp < start { continue }
            let day = cal.startOfDay(for: meal.timestamp)
            let t = meal.totals
            var totals = byDay[day] ?? DayTotals(date: day, calories: 0, protein: 0, carbs: 0, fat: 0, water: 0)
            totals.calories += t.calories
            totals.protein += t.protein
            totals.carbs += t.carbs
            totals.fat += t.fat
            totals.water += t.waterOunces
            byDay[day] = totals
        }
        return byDay.values.sorted { $0.date < $1.date }
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
    private func chartPoints(from daysInRange: [DayTotals]) -> [MetricPoint] {
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

    private func average(_ metric: Metric, over days: [DayTotals]) -> Double {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.value(metric) } / Double(days.count)
    }

    // MARK: Body

    var body: some View {
        let days = daysInRange
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if days.isEmpty {
                        LuxNote("Log some meals and your trends will show here.", size: 15)
                            .padding(.top, 40)
                    } else if visibleMetrics.isEmpty {
                        LuxNote("Every nutrient is hidden — tap one below to show it.", size: 15)
                            .padding(.top, 40)
                    } else {
                        trendChart(points: chartPoints(from: days))
                            .padding(.top, 18)
                    }

                    if !days.isEmpty {
                        LuxSectionHeader(text: "AVERAGE PER DAY")
                            .padding(.top, 24)
                            .padding(.bottom, 2)

                        ForEach(Metric.allCases) { metric in
                            metricRow(metric, days: days)
                        }

                        LuxNote("Each line is that nutrient as a percent of your daily goal. Tap a row to show or hide it.")
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, Lux.hPad)
                .padding(.bottom, OrbNavBar.orbOnlyClearance)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header(days: days)
            }
            .luxScreen()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Header

    private func header(days: [DayTotals]) -> some View {
        VStack(spacing: 0) {
            LuxHeader(
                title: "TRENDS",
                subtitle: "How the days add up."
            ) {
                Text(sinceLabel(days: days))
                    .font(Lux.smallcaps(10))
                    .tracking(3)
                    .foregroundStyle(Lux.goldLabel)
            } trailing: {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Lux.cream)
            }

            LuxSwitcher(
                options: TrendRange.allCases.map { ($0, $0.title.uppercased()) },
                selection: $range,
                spacing: 14
            )
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(Lux.ground)
    }

    /// "SINCE 19 JULY" — the first day with data in the current range, which
    /// says more than repeating the range name already shown in the picker.
    private func sinceLabel(days: [DayTotals]) -> String {
        guard let first = days.first?.date else { return "NO DATA" }
        return "SINCE \(first.formatted(.dateTime.day().month(.wide)))".uppercased()
    }

    // MARK: Chart

    private func trendChart(points: [MetricPoint]) -> some View {
        Chart {
            RuleMark(y: .value("Goal", 100))
                .foregroundStyle(Lux.cream.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("GOAL")
                        .font(Lux.smallcaps(7))
                        .tracking(1.5)
                        .foregroundStyle(Lux.cream.opacity(0.45))
                }
            ForEach(points) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("% of goal", point.percent)
                )
                .foregroundStyle(point.metric.color)
                .lineStyle(point.metric.lineStyle)
                .symbol(point.metric.symbol)
                .symbolSize(point.metric == .calories ? 36 : 24)
                .interpolationMethod(.catmullRom)
            }
        }
        // The series share one hue family, so weight, dash and mark shape do
        // the separating that colour used to. That also makes the chart
        // readable without colour vision, which the old palette was not.
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Lux.cream.opacity(0.1))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))%")
                            .font(Lux.smallcaps(9))
                            .foregroundStyle(Lux.cream.opacity(0.45))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Lux.cream.opacity(0.1))
                AxisValueLabel()
                    .font(Lux.smallcaps(9))
                    .foregroundStyle(Lux.cream.opacity(0.45))
            }
        }
        .chartLegend(.hidden)   // the tappable ledger below is the legend
        .frame(height: 240)
        .luxPanel()
    }

    // MARK: Average ledger (also the legend + series toggles)

    private func metricRow(_ metric: Metric, days: [DayTotals]) -> some View {
        let on = selectedMetrics.contains(metric)
        return Button {
            if on { selectedMetrics.remove(metric) } else { selectedMetrics.insert(metric) }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(metric.color)
                    .frame(width: 8, height: 8)
                    .opacity(on ? 1 : 0.3)
                Text(metric.title.uppercased())
                    .font(Lux.smallcaps(9))
                    .tracking(2)
                    .foregroundStyle(on ? Lux.cream.opacity(0.7) : Lux.cream.opacity(0.3))
                Spacer()
                Text("\(Int(average(metric, over: days).rounded()))")
                    .font(Lux.serif(20))
                    .monospacedDigit()
                    .foregroundStyle(on ? Lux.gold : Lux.cream.opacity(0.3))
                Text(metric.unit.uppercased())
                    .font(Lux.smallcaps(7))
                    .tracking(1.5)
                    .foregroundStyle(Lux.cream.opacity(on ? 0.45 : 0.25))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .luxRow(vertical: 11)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Series styling

extension Metric {
    /// Weight and dash carry series identity now that every line is gold.
    /// Calories is heaviest and solid because it is the headline; the dashed
    /// pairs sit next to each other on the ladder and need the extra help.
    var lineStyle: StrokeStyle {
        switch self {
        case .calories: return StrokeStyle(lineWidth: 2.2)
        case .protein:  return StrokeStyle(lineWidth: 1.4)
        case .carbs:    return StrokeStyle(lineWidth: 1.4, dash: [5, 3])
        case .fat:      return StrokeStyle(lineWidth: 1.4, dash: [2, 2.5])
        case .water:    return StrokeStyle(lineWidth: 1.2)
        }
    }

    var symbol: BasicChartSymbolShape {
        switch self {
        case .calories: return .circle
        case .protein:  return .square
        case .carbs:    return .diamond
        case .fat:      return .triangle
        case .water:    return .plus
        }
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
    /// Series colour: the five-step gold ladder, brightest at the top of the
    /// stack so calories reads first. Hue no longer separates the series — the
    /// chart leans on line weight, dash pattern, and mark shape instead, which
    /// is also what makes it legible to colour-blind readers.
    var color: Color {
        switch self {
        case .calories: return Lux.goldBright
        case .protein:  return Lux.goldMidBright
        case .carbs:    return Lux.gold
        case .fat:      return Lux.goldDeep
        case .water:    return Lux.bronze
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

