import WidgetKit
import SwiftUI
import AppIntents
import SwiftData

// MARK: - Interactive intent

/// Logging a mood from a widget tap has to happen without opening the app —
/// that's the whole point of a silent check-in. `perform()` writes straight
/// into the shared store via `CheckInWriter` and asks WidgetKit to reload so
/// the "today" mood shown on the widget updates immediately.
struct LogMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Mood"
    static var description = IntentDescription("Log how you're feeling right now.")
    static var openAppWhenRun = false

    @Parameter(title: "Mood")
    var mood: Int

    init() {}
    init(mood: Int) { self.mood = mood }

    func perform() async throws -> some IntentResult {
        _ = CheckInWriter.logInSharedStore(mood: mood)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Timeline

struct MoodEntry: TimelineEntry {
    let date: Date
    /// Today's most recent check-in, if any — nil means nothing logged yet
    /// today, in which case the widget shows a gentle prompt instead of a
    /// score.
    let latestMood: Int?
    let latestMoodTime: Date?
}

struct MoodProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoodEntry {
        MoodEntry(date: .now, latestMood: 4, latestMoodTime: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (MoodEntry) -> Void) {
        completion(todaysEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoodEntry>) -> Void) {
        let now = Date()
        let entry = todaysEntry(now: now)

        // A mood check-in isn't time-sensitive enough to poll for — the only
        // thing that actually goes stale on its own is the day rolling over,
        // so refreshing on the hour is cheap and catches midnight without
        // burning the widget's refresh budget on minute-level accuracy.
        let nextHour = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3600)

        completion(Timeline(entries: [entry], policy: .after(nextHour)))
    }

    /// Reads the shared store directly rather than going through
    /// `AppModelContainer.shared`, since that singleton would otherwise keep
    /// a second open container alive for the lifetime of the extension.
    private func todaysEntry(now: Date = .now) -> MoodEntry {
        guard let container = try? ModelContainer(
            for: Schema(AppModelContainer.models),
            configurations: [sharedConfiguration()]
        ) else {
            return MoodEntry(date: now, latestMood: nil, latestMoodTime: nil)
        }

        let context = ModelContext(container)
        let startOfDay = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.timestamp >= startOfDay && $0.moodScore != nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let latest = (try? context.fetch(descriptor))?.first
        return MoodEntry(date: now, latestMood: latest?.moodScore, latestMoodTime: latest?.timestamp)
    }

    private func sharedConfiguration() -> ModelConfiguration {
        let schema = Schema(AppModelContainer.models)
        if let url = AppModelContainer.storeURL {
            return ModelConfiguration(schema: schema, url: url)
        }
        return ModelConfiguration(schema: schema)
    }
}

// MARK: - Shared pieces

/// The five-emoji row that does the actual logging. Used on every family
/// that has room for it (home screen small/medium, and lock-screen
/// rectangular when it fits) — each button is its own tap target so logging
/// is a single touch, no confirmation step.
private struct MoodButtonRow: View {
    var font: Font = .title2
    var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Mood.range, id: \.self) { score in
                Button(intent: LogMoodIntent(mood: score)) {
                    Text(Mood.emoji(for: score))
                        .font(font)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Mood.label(for: score))
            }
        }
    }
}

private func todaySummary(_ entry: MoodEntry) -> String {
    guard let mood = entry.latestMood else { return "How are you feeling?" }
    return "\(Mood.emoji(for: mood)) \(Mood.label(for: mood))"
}

// MARK: - Home screen views

private struct SmallView: View {
    let entry: MoodEntry
    var body: some View {
        VStack(spacing: 10) {
            Text("How are you feeling?")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            MoodButtonRow(font: .title3, spacing: 5)
            if let mood = entry.latestMood {
                Text("Today: \(Mood.emoji(for: mood)) \(Mood.label(for: mood))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediumView: View {
    let entry: MoodEntry
    var body: some View {
        VStack(spacing: 12) {
            Text(entry.latestMood == nil ? "How are you feeling?" : "Feeling different now?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            MoodButtonRow(font: .largeTitle, spacing: 14)
            if let mood = entry.latestMood {
                Text("Last logged today: \(Mood.emoji(for: mood)) \(Mood.label(for: mood))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Lock-screen (accessory) views

/// `accessoryRectangular` is the one lock-screen family with enough width to
/// stay interactive: it shows the five emoji as buttons at a smaller size.
/// If that ever feels cramped on a given device this is where you'd fall
/// back to a single "Log" button, but the standard lock-screen widget frame
/// comfortably fits five small glyphs plus a title line.
private struct RectangularAccessory: View {
    let entry: MoodEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(todaySummary(entry))
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
            MoodButtonRow(font: .body, spacing: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `accessoryCircular` and `accessoryInline` are display-only: WidgetKit
/// doesn't give a circular/inline accessory enough room for five distinct
/// tap targets, so instead of a cramped, easy-to-mistap row these just show
/// today's mood (or a prompt) and tapping anywhere opens the app via
/// `widgetURL`, where logging is one tap on the Today card.
private struct CircularAccessory: View {
    let entry: MoodEntry
    var body: some View {
        VStack(spacing: 2) {
            Text(entry.latestMood.map(Mood.emoji) ?? "🙂")
                .font(.title2)
            Text(entry.latestMood.map(Mood.label) ?? "Log")
                .font(.system(size: 9))
        }
        .widgetAccentable()
        .widgetURL(URL(string: "mindlog://checkin"))
    }
}

private struct InlineAccessory: View {
    let entry: MoodEntry
    var body: some View {
        Text(todaySummary(entry))
            .widgetURL(URL(string: "mindlog://checkin"))
    }
}

// MARK: - Entry view

struct MindLogWidgetEntryView: View {
    var entry: MoodEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(entry: entry)
        case .accessoryCircular:
            CircularAccessory(entry: entry)
        case .accessoryRectangular:
            RectangularAccessory(entry: entry)
        case .accessoryInline:
            InlineAccessory(entry: entry)
        default:
            MediumView(entry: entry)
        }
    }
}

// MARK: - Configuration

struct MindLogCheckInWidget: Widget {
    let kind = "MindLogCheckInWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodProvider()) { entry in
            MindLogWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mood Check-In")
        .description("Log a mood in one tap, from your lock screen or home screen.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
    }
}

@main
struct MindLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        MindLogCheckInWidget()
    }
}
