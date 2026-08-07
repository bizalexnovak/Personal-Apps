import WidgetKit
import SwiftUI

// MARK: - Timeline

struct CheckInEntry: TimelineEntry {
    let date: Date
    let snapshot: CheckInSnapshot
}

/// No configuration to pick — every mood button is a fixed, always-visible
/// action, so a plain `TimelineProvider` is all this needs.
struct CheckInProvider: TimelineProvider {
    func placeholder(in context: Context) -> CheckInEntry {
        CheckInEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (CheckInEntry) -> Void) {
        completion(CheckInEntry(date: .now, snapshot: CheckInSnapshotStore.read().resolved(for: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CheckInEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let today = CheckInSnapshotStore.read().resolved(for: now)
        var entries = [CheckInEntry(date: now, snapshot: today)]

        // Queue a reset entry exactly at the next midnight so a logged mood
        // clears itself without the app ever running. Nothing to carry
        // forward — yesterday's mood shouldn't linger into a new day.
        if let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) {
            entries.append(CheckInEntry(
                date: nextMidnight,
                snapshot: CheckInSnapshot(day: calendar.startOfDay(for: nextMidnight))
            ))
            completion(Timeline(entries: entries, policy: .after(nextMidnight)))
            return
        }

        // Fallback: LogMoodIntent reloads on every tap; refresh in 30 min otherwise.
        let next = calendar.date(byAdding: .minute, value: 30, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

// MARK: - Mood glyphs

/// Local copy of the app's five-point scale — the widget target can't see
/// `Mood` in the app's Models folder, and this is small enough not to be
/// worth sharing.
private enum WidgetMood {
    static func emoji(for score: Int) -> String {
        switch score {
        case ...1: return "😞"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        default: return "😄"
        }
    }

    static func label(for score: Int) -> String {
        switch score {
        case ...1: return "Rough"
        case 2: return "Low"
        case 3: return "Okay"
        case 4: return "Good"
        default: return "Great"
        }
    }
}

/// "Last: 🙂 at 4:12 PM" — quiet acknowledgement that today's already been
/// shown up for. Never a streak, never a count, never a nag: MindLog rewards
/// showing up once and stops there.
private func lastLoggedText(_ snapshot: CheckInSnapshot) -> String? {
    guard let mood = snapshot.latestMood, let at = snapshot.latestMoodAt else { return nil }
    let time = at.formatted(date: .omitted, time: .shortened)
    return "Last: \(WidgetMood.emoji(for: mood)) at \(time)"
}

// MARK: - Mood button row

/// One tappable mood emoji — used on every family that has room for five.
private struct MoodButton: View {
    let score: Int
    var font: Font = .system(size: 24)

    var body: some View {
        Button(intent: LogMoodIntent(mood: MoodChoice(rawValue: score) ?? .okay)) {
            Text(WidgetMood.emoji(for: score))
                .font(font)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WidgetMood.label(for: score))
    }
}

private struct MoodRow: View {
    var spacing: CGFloat = 8
    var font: Font = .system(size: 24)

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { score in
                MoodButton(score: score, font: font)
            }
        }
    }
}

// MARK: - Widget views

private struct RectangularView: View {
    let snapshot: CheckInSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let text = lastLoggedText(snapshot) {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("How are you?")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            MoodRow(spacing: 6, font: .system(size: 15))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SmallView: View {
    let snapshot: CheckInSnapshot

    var body: some View {
        VStack(spacing: 8) {
            Text(lastLoggedText(snapshot) ?? "How are you?")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            // Two rows of buttons — a systemSmall widget isn't wide enough
            // for five in one line at a tappable size.
            HStack(spacing: 8) {
                MoodButton(score: 1)
                MoodButton(score: 2)
                MoodButton(score: 3)
            }
            HStack(spacing: 8) {
                MoodButton(score: 4)
                MoodButton(score: 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediumView: View {
    let snapshot: CheckInSnapshot

    var body: some View {
        VStack(spacing: 10) {
            Text(lastLoggedText(snapshot) ?? "How are you feeling right now?")
                .font(.caption)
                .foregroundStyle(.secondary)
            MoodRow(spacing: 16, font: .system(size: 30))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Lock-screen circle: display only, no five-way tap target fits. Shows the
/// day's mood if there is one, or a plain prompt glyph; tapping falls through
/// to the widget's default behaviour of opening the app.
private struct CircularView: View {
    let snapshot: CheckInSnapshot

    var body: some View {
        if let mood = snapshot.latestMood {
            Text(WidgetMood.emoji(for: mood))
                .font(.system(size: 26))
                .accessibilityLabel("Last mood: \(WidgetMood.label(for: mood))")
        } else {
            Image(systemName: "face.smiling")
                .font(.system(size: 22))
                .accessibilityLabel("How are you feeling?")
        }
    }
}

struct MindLogWidgetEntryView: View {
    var entry: CheckInEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            RectangularView(snapshot: entry.snapshot)
        case .systemSmall:
            SmallView(snapshot: entry.snapshot)
        default:
            MediumView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Configuration

struct MindLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MindLogSharing.widgetKind, provider: CheckInProvider()) { entry in
            MindLogWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mood Check-In")
        .description("Log how you're feeling in one tap, right from your lock screen or home screen.")
        .supportedFamilies([
            .accessoryRectangular, .accessoryCircular, .systemSmall, .systemMedium,
        ])
    }
}

@main
struct MindLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        MindLogWidget()
    }
}
