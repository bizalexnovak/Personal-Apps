import SwiftUI
import SwiftData
import UIKit

/// The Today tab: a day-by-day dashboard. Chevrons step back and forward
/// through days (never into the future), tapping the date opens a calendar,
/// and everything below — score ring, mood, activities, entries — reflects
/// the selected day.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appAccent) private var accent
    @Environment(\.appBackground) private var appBackground
    @Environment(\.metricPalette) private var palette
    @EnvironmentObject private var hub: AppHub

    @Query(sort: \JournalEntry.timestamp, order: .reverse) private var entries: [JournalEntry]
    @Query(sort: \ActivityLog.timestamp, order: .reverse) private var logs: [ActivityLog]

    @AppStorage(GoalKeys.scoreGoal) private var scoreGoal = PracticeScore.defaultGoal
    @AppStorage(ProfileKeys.firstName) private var firstName = ""

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var showCalendar = false
    @State private var showActivitySheet = false
    @State private var editingEntry: JournalEntry?

    private var calendar: Calendar { .current }
    private var isToday: Bool { calendar.isDateInToday(selectedDay) }

    private var dayEntries: [JournalEntry] {
        entries.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedDay) }
    }

    private var dayLogs: [ActivityLog] {
        logs.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedDay) }
    }

    private var dayInput: PracticeScore.DayInput {
        PracticeScore.dayInput(entries: dayEntries, logs: dayLogs)
    }

    private var dayScore: Double { PracticeScore.score(for: dayInput) }

    private var dayMinutes: Double { dayLogs.reduce(0) { $0 + $1.minutes } }

    private var streak: Int {
        InsightsEngine.currentStreak(
            days: DayAggregator.summaries(entries: entries, logs: logs, calendar: calendar),
            today: .now,
            calendar: calendar
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    dayHeader
                    scoreCard
                    moodCard
                    activitiesCard
                    journalCard
                }
                .padding()
            }
            .appBackground(appBackground)
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showCalendar) { calendarSheet }
        .sheet(isPresented: $showActivitySheet) {
            ActivityLogSheet(day: selectedDay)
        }
        .sheet(item: $editingEntry) { entry in
            JournalEntryDetailView(entry: entry)
        }
    }

    private var greeting: String {
        let hour = calendar.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let name = firstName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    // MARK: - Day navigation

    private var dayHeader: some View {
        HStack {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            Spacer()
            Button {
                showCalendar = true
            } label: {
                Text(dayTitle)
                    .font(.headline)
            }
            Spacer()
            if isToday {
                // Keep the chevron footprint so the title stays centred.
                Image(systemName: "chevron.right").font(.headline).opacity(0.15)
            } else {
                HStack(spacing: 12) {
                    Button {
                        step(1)
                    } label: {
                        Image(systemName: "chevron.right").font(.headline)
                    }
                    Button("Today") {
                        withAnimation { selectedDay = calendar.startOfDay(for: .now) }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var dayTitle: String {
        if isToday { return "Today" }
        if calendar.isDateInYesterday(selectedDay) { return "Yesterday" }
        return selectedDay.formatted(date: .abbreviated, time: .omitted)
    }

    private func step(_ direction: Int) {
        guard let next = calendar.date(byAdding: .day, value: direction, to: selectedDay) else { return }
        guard next <= calendar.startOfDay(for: .now) else { return }
        withAnimation { selectedDay = next }
    }

    private var calendarSheet: some View {
        NavigationStack {
            DatePicker(
                "Day",
                selection: Binding(
                    get: { selectedDay },
                    set: { selectedDay = calendar.startOfDay(for: $0) }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Jump to a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCalendar = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Score

    private var scoreCard: some View {
        HStack(spacing: 18) {
            ScoreRing(score: dayScore, goal: scoreGoal, color: palette.score)
                .frame(width: 108, height: 108)
            VStack(alignment: .leading, spacing: 6) {
                Text("Practice score")
                    .font(.headline)
                Text(scoreLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if streak >= 2 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var scoreLine: String {
        if dayScore <= 0 {
            return isToday
                ? "Nothing yet — a check-in or a few mindful minutes gets you started."
                : "Nothing logged this day."
        }
        var parts: [String] = []
        if dayMinutes > 0 { parts.append("\(Int(dayMinutes.rounded())) min practiced") }
        if dayInput.journaled { parts.append("journaled") }
        if dayInput.checkedIn { parts.append("checked in") }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    // MARK: - Mood

    private var dayMoods: [JournalEntry] {
        dayEntries.filter { $0.moodScore != nil }.sorted { $0.timestamp < $1.timestamp }
    }

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayMoods.isEmpty ? (isToday ? "How are you feeling?" : "Mood") : "Mood")
                .font(.headline)
            if dayMoods.isEmpty {
                if isToday {
                    MoodPicker(selection: Binding(
                        get: { nil },
                        set: { newValue in
                            if let newValue { saveCheckIn(newValue) }
                        }
                    ))
                    .frame(maxWidth: .infinity)
                    Text("One tap — it's saved to your journal as a check-in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No mood recorded this day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 14) {
                    ForEach(dayMoods) { entry in
                        VStack(spacing: 2) {
                            Text(Mood.emoji(for: entry.moodScore ?? 3))
                                .font(.system(size: 30))
                            Text(timeText(entry.timestamp))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if isToday {
                        Button {
                            hub.goVoiceJournal()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(accent)
                        }
                        .accessibilityLabel("Add another check-in")
                    }
                }
            }
        }
        .card()
    }

    private func saveCheckIn(_ score: Int) {
        let entry = JournalEntry(source: EntrySource.checkIn, moodScore: score)
        context.insert(entry)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Activities

    private var activitiesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activities")
                    .font(.headline)
                Spacer()
                Button {
                    showActivitySheet = true
                } label: {
                    Label("Log", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
            }
            if dayLogs.isEmpty {
                Text(isToday
                     ? "Meditate, walk, call a friend — log anything you do for your mind."
                     : "No activities logged this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dayLogs) { log in
                    HStack(spacing: 10) {
                        Image(systemName: log.activity.icon)
                            .font(.subheadline)
                            .foregroundStyle(accent)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(log.activity.name)
                                .font(.subheadline.weight(.medium))
                            if !log.note.isEmpty {
                                Text(log.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("\(Int(log.minutes.rounded())) min")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button(role: .destructive) {
                            context.delete(log)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Text("Hold an activity to delete it.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .card()
    }

    // MARK: - Journal

    private var journalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Journal")
                    .font(.headline)
                Spacer()
                if isToday {
                    Button {
                        hub.goVoiceJournal()
                    } label: {
                        Label("New entry", systemImage: "mic.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            let written = dayEntries.filter { !$0.isCheckIn }
            if written.isEmpty {
                Text(isToday
                     ? "Nothing written yet. Say what's on your mind — thirty seconds counts."
                     : "No entries this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(written) { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.moodScore.map(Mood.emoji(for:)) ?? "📝")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.snippet)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                Text(timeText(entry.timestamp))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
        }
        .card()
    }
}

/// Daily goal keys. Not secrets — plain AppStorage.
enum GoalKeys {
    static let scoreGoal = "goal_score"
}

/// Personal profile fields (non-secret) shown under Settings → Profile.
enum ProfileKeys {
    static let firstName = "profile_first_name"
}
