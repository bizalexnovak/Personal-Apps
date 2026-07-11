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

    func snapshot(for configuration: SelectMetricIntent, in context: Context) async -> MacroEntry {
        MacroEntry(date: .now, snapshot: WidgetDataStore.read() ?? .empty, metric: configuration.metric)
    }

    func timeline(for configuration: SelectMetricIntent, in context: Context) async -> Timeline<MacroEntry> {
        let entry = MacroEntry(date: .now, snapshot: WidgetDataStore.read() ?? .empty, metric: configuration.metric)
        // The app reloads on data changes; this is a fallback refresh.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(next))
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
    var diameter: CGFloat = 52
    var lineWidth: CGFloat = 6
    var valueFont: Font = .system(size: 14, weight: .semibold)

    private var progress: Double { target > 0 ? min(value / target, 1) : 0 }

    var body: some View {
        VStack(spacing: 4) {
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

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            WidgetRing(
                value: metric.value(snapshot), target: metric.target(snapshot),
                color: metric.color, label: metric.label, showLabel: false,
                centerText: "\(Int(metric.value(snapshot).rounded()))/\(Int(metric.target(snapshot).rounded()))",
                diameter: 90, lineWidth: 10, valueFont: .system(size: 24, weight: .bold)
            )
            Spacer(minLength: 0)
            Text(metric.label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                   diameter: 52, lineWidth: 6, valueFont: .system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
    }
}

struct MacroLogWidgetEntryView: View {
    var entry: MacroEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(snapshot: entry.snapshot, metric: entry.metric)
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
        .description("Your calories and macros logged today. Edit the small widget to pick a metric.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MacroLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        MacroLogWidget()
    }
}
