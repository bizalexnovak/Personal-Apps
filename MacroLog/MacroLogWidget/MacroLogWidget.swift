import WidgetKit
import SwiftUI

// MARK: - Timeline

struct MacroEntry: TimelineEntry {
    let date: Date
    let snapshot: DayNutritionSnapshot
}

struct MacroProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacroEntry {
        MacroEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (MacroEntry) -> Void) {
        completion(MacroEntry(date: .now, snapshot: WidgetDataStore.read() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacroEntry>) -> Void) {
        let entry = MacroEntry(date: .now, snapshot: WidgetDataStore.read() ?? .empty)
        // The app reloads the timeline whenever data changes; this is just a
        // fallback refresh so a long-open widget doesn't go stale.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Colors (match the app's default metric palette)

private enum WidgetColors {
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
    var lineWidth: CGFloat = 6
    var valueFont: Font = .system(size: 13, weight: .semibold)

    private var progress: Double { target > 0 ? min(value / target, 1) : 0 }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value.rounded()))")
                    .font(valueFont.monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(2)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Widget views

private struct SmallView: View {
    let snapshot: DayNutritionSnapshot
    var body: some View {
        VStack(spacing: 6) {
            WidgetRing(
                value: snapshot.calories, target: snapshot.calorieTarget,
                color: WidgetColors.calories, label: "kcal",
                lineWidth: 9, valueFont: .system(size: 22, weight: .bold)
            )
            Text("of \(Int(snapshot.calorieTarget.rounded())) kcal")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(4)
    }
}

private struct MediumView: View {
    let snapshot: DayNutritionSnapshot
    var body: some View {
        HStack(spacing: 10) {
            WidgetRing(value: snapshot.calories, target: snapshot.calorieTarget,
                       color: WidgetColors.calories, label: "kcal")
            WidgetRing(value: snapshot.protein, target: snapshot.proteinTarget,
                       color: WidgetColors.protein, label: "protein")
            WidgetRing(value: snapshot.carbs, target: snapshot.carbTarget,
                       color: WidgetColors.carbs, label: "carbs")
            WidgetRing(value: snapshot.fat, target: snapshot.fatTarget,
                       color: WidgetColors.fat, label: "fat")
            WidgetRing(value: snapshot.water, target: snapshot.waterTarget,
                       color: WidgetColors.water, label: "water")
        }
        .padding(.vertical, 6)
    }
}

struct MacroLogWidgetEntryView: View {
    var entry: MacroEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(snapshot: entry.snapshot)
        default:
            MediumView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Configuration

struct MacroLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetDataStore.widgetKind, provider: MacroProvider()) { entry in
            MacroLogWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today's Macros")
        .description("Your calories and macros logged today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MacroLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        MacroLogWidget()
    }
}
