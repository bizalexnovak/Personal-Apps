import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configurable metric (small widget)

enum WidgetMetric: String, AppEnum {
    case calories, protein, carbs, fat, water

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Metric" }
    static var caseDisplayRepresentations: [WidgetMetric: DisplayRepresentation] {
        [
            .calories: "Calories",
            .protein: "Protein",
            .carbs: "Carbs",
            .fat: "Fat",
            .water: "Water",
        ]
    }

    func value(_ s: DayNutritionSnapshot) -> Double {
        switch self {
        case .calories: return s.calories
        case .protein: return s.protein
        case .carbs: return s.carbs
        case .fat: return s.fat
        case .water: return s.water
        }
    }

    func target(_ s: DayNutritionSnapshot) -> Double {
        switch self {
        case .calories: return s.calorieTarget
        case .protein: return s.proteinTarget
        case .carbs: return s.carbTarget
        case .fat: return s.fatTarget
        case .water: return s.waterTarget
        }
    }

    var color: Color {
        switch self {
        case .calories: return WidgetColors.calories
        case .protein: return WidgetColors.protein
        case .carbs: return WidgetColors.carbs
        case .fat: return WidgetColors.fat
        case .water: return WidgetColors.water
        }
    }

    var unit: String {
        switch self {
        case .calories: return "kcal"
        case .water: return "oz"
        default: return "g"
        }
    }

    var label: String {
        switch self {
        case .calories: return "Calories"
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        case .water: return "Water"
        }
    }
}

/// The widget's configuration — picks which metric the small size shows.
struct SelectMetricIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Metric"
    static var description = IntentDescription("Pick which metric the small widget shows.")

    @Parameter(title: "Metric", default: .calories)
    var metric: WidgetMetric
}

// MARK: - Timeline

struct MacroEntry: TimelineEntry {
    let date: Date
    let snapshot: DayNutritionSnapshot
    let metric: WidgetMetric
}

struct MacroProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MacroEntry {
        MacroEntry(date: .now, snapshot: .empty, metric: .calories)
    }

    /// The stored snapshot, zeroed if it's from a previous day (the app hasn't
    /// been opened yet today) so we never show yesterday's totals.
    private func currentSnapshot(now: Date = .now) -> DayNutritionSnapshot {
        let cal = Calendar.current
        let stored = WidgetDataStore.read() ?? .empty
        return cal.isDate(stored.date, inSameDayAs: now)
            ? stored
            : stored.clearedForNewDay(date: cal.startOfDay(for: now))
    }

    func snapshot(for configuration: SelectMetricIntent, in context: Context) async -> MacroEntry {
        MacroEntry(date: .now, snapshot: currentSnapshot(), metric: configuration.metric)
    }

    func timeline(for configuration: SelectMetricIntent, in context: Context) async -> Timeline<MacroEntry> {
        let cal = Calendar.current
        let now = Date()
        let metric = configuration.metric
        let todaySnapshot = currentSnapshot(now: now)
        var entries = [MacroEntry(date: now, snapshot: todaySnapshot, metric: metric)]

        // Queue a reset entry exactly at the next midnight so the widget rolls
        // over to a clean day on its own, even if the app is never opened.
        if let nextMidnight = cal.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) {
            entries.append(MacroEntry(
                date: nextMidnight,
                snapshot: todaySnapshot.clearedForNewDay(date: nextMidnight),
                metric: metric
            ))
            return Timeline(entries: entries, policy: .after(nextMidnight))
        }

        // Fallback: the app reloads on data changes; refresh in 30 min otherwise.
        let next = cal.date(byAdding: .minute, value: 30, to: now) ?? now
        return Timeline(entries: entries, policy: .after(next))
    }
}

// MARK: - Colors (match the app's default metric palette)

enum WidgetColors {
    static let calories = Color(.sRGB, red: 0.961, green: 0.486, blue: 0.0)
    static let protein = Color(.sRGB, red: 0.898, green: 0.224, blue: 0.208)
    static let carbs = Color(.sRGB, red: 0.118, green: 0.533, blue: 0.898)
    static let fat = Color(.sRGB, red: 0.722, green: 0.576, blue: 0.039)
    static let water = Color(.sRGB, red: 0.0, green: 0.627, blue: 0.690)
}

// MARK: - Ring

private struct WidgetRing: View {
    let value: Double
    let target: Double
    let color: Color
    let label: String
    /// Overrides the centre text (e.g. "24/128"); defaults to just the value.
    var centerText: String? = nil
    var showLabel: Bool = true
    /// Gap between the ring and the label below it.
    var labelSpacing: CGFloat = 4
    var diameter: CGFloat = 52
    var lineWidth: CGFloat = 6
    var valueFont: Font = .system(size: 14, weight: .semibold)

    private var progress: Double { target > 0 ? min(value / target, 1) : 0 }

    var body: some View {
        VStack(spacing: labelSpacing) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(centerText ?? "\(Int(value.rounded()))")
                    .font(valueFont.monospacedDigit())
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(lineWidth)
            }
            .frame(width: diameter, height: diameter)
            if showLabel {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Widget views

private struct SmallView: View {
    let snapshot: DayNutritionSnapshot
    let metric: WidgetMetric

    private var centerText: String {
        "\(Int(metric.value(snapshot).rounded()))/\(Int(metric.target(snapshot).rounded()))"
    }
    private var progress: Double {
        let t = metric.target(snapshot)
        return t > 0 ? min(metric.value(snapshot) / t, 1) : 0
    }

    var body: some View {
        // Absolute placement via the widget's real size so the ring and label
        // land exactly where intended regardless of the widget's sizing quirks.
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let diameter = side * 0.66
            let lineWidth: CGFloat = 10

            ZStack {
                Circle().stroke(metric.color.opacity(0.2), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(metric.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(centerText)
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(lineWidth)
            }
            .frame(width: diameter, height: diameter)
            .position(x: geo.size.width / 2, y: geo.size.height * 0.40)

            Text(metric.label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.secondary)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.93)
        }
    }
}

private struct MediumView: View {
    let snapshot: DayNutritionSnapshot
    var body: some View {
        HStack(spacing: 4) {
            ring(snapshot.calories, snapshot.calorieTarget, WidgetColors.calories, "kcal")
            ring(snapshot.protein, snapshot.proteinTarget, WidgetColors.protein, "protein")
            ring(snapshot.carbs, snapshot.carbTarget, WidgetColors.carbs, "carbs")
            ring(snapshot.fat, snapshot.fatTarget, WidgetColors.fat, "fat")
            ring(snapshot.water, snapshot.waterTarget, WidgetColors.water, "water")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ring(_ value: Double, _ target: Double, _ color: Color, _ label: String) -> some View {
        WidgetRing(value: value, target: target, color: color, label: label,
                   labelSpacing: 14,
                   diameter: 52, lineWidth: 6, valueFont: .system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Lock-screen (accessory) views

private struct CircularAccessory: View {
    let snapshot: DayNutritionSnapshot
    let metric: WidgetMetric
    var body: some View {
        Gauge(value: metric.target(snapshot) > 0 ? min(metric.value(snapshot) / metric.target(snapshot), 1) : 0) {
            Text(metric.unit)
        } currentValueLabel: {
            Text("\(Int(metric.value(snapshot).rounded()))")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

private struct RectangularAccessory: View {
    let snapshot: DayNutritionSnapshot
    let metric: WidgetMetric
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(snapshot.calories.rounded()))/\(Int(snapshot.calorieTarget.rounded())) kcal")
                .font(.headline)
            Text("P \(Int(snapshot.protein.rounded()))  C \(Int(snapshot.carbs.rounded()))  F \(Int(snapshot.fat.rounded()))")
                .font(.caption)
            Text("Water \(Int(snapshot.water.rounded()))/\(Int(snapshot.waterTarget.rounded())) oz")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineAccessory: View {
    let snapshot: DayNutritionSnapshot
    let metric: WidgetMetric
    var body: some View {
        Text("\(metric.label) \(Int(metric.value(snapshot).rounded()))/\(Int(metric.target(snapshot).rounded())) \(metric.unit)")
    }
}

struct MacroLogWidgetEntryView: View {
    var entry: MacroEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(snapshot: entry.snapshot, metric: entry.metric)
        case .accessoryCircular:
            CircularAccessory(snapshot: entry.snapshot, metric: entry.metric)
        case .accessoryRectangular:
            RectangularAccessory(snapshot: entry.snapshot, metric: entry.metric)
        case .accessoryInline:
            InlineAccessory(snapshot: entry.snapshot, metric: entry.metric)
        default:
            MediumView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Configuration

struct MacroLogWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetDataStore.widgetKind,
            intent: SelectMetricIntent.self,
            provider: MacroProvider()
        ) { entry in
            MacroLogWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today's Macros")
        .description("Your calories and macros logged today. Edit the widget to pick a metric.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

@main
struct MacroLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        MacroLogWidget()
    }
}
