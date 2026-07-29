import SwiftUI
import SwiftData
import Charts

/// The Trends tab: mood over time, practice score over time, activity
/// minutes, and the insight cards that relate them ("on days you meditate,
/// your mood averages higher"). All computed locally from the day summaries.
struct TrendsView: View {
    @Environment(\.appBackground) private var appBackground
    @Environment(\.metricPalette) private var palette

    @Query(sort: \JournalEntry.timestamp) private var entries: [JournalEntry]
    @Query(sort: \ActivityLog.timestamp) private var logs: [ActivityLog]

    @AppStorage(GoalKeys.scoreGoal) private var scoreGoal = PracticeScore.defaultGoal
    @AppStorage("trends_show_sentiment") private var showSentiment = false

    @State private var range = TrendRange.month

    enum TrendRange: String, CaseIterable, Identifiable {
        case week = "1W", month = "1M", threeMonths = "3M", year = "1Y", all = "All"
        var id: String { rawValue }

        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .threeMonths: return 90
            case .year: return 365
            case .all: return nil
            }
        }
    }

    private var rangeStart: Date? {
        guard let days = range.days else { return nil }
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: .now))
    }

    private var summaries: [DaySummary] {
        let all = DayAggregator.summaries(entries: entries, logs: logs)
        guard let start = rangeStart else { return all }
        return all.filter { $0.date >= start }
    }

    private var rangedEntries: [JournalEntry] {
        guard let start = rangeStart else { return entries }
        return entries.filter { $0.timestamp >= start }
    }

    private var rangedLogs: [ActivityLog] {
        guard let start = rangeStart else { return logs }
        return logs.filter { $0.timestamp >= start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Range", selection: $range) {
                        ForEach(TrendRange.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)

                    if summaries.isEmpty {
                        ContentUnavailableView(
                            "Nothing here yet",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Check in, journal, or log an activity and your trends start filling in.")
                        )
                        .padding(.top, 40)
                    } else {
                        statsRow
                        moodChart
                        scoreChart
                        minutesChart
                        insightsSection
                    }
                }
                .padding()
            }
            .appBackground(appBackground)
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        let allSummaries = DayAggregator.summaries(entries: entries, logs: logs)
        let current = InsightsEngine.currentStreak(days: allSummaries, today: .now)
        let best = InsightsEngine.bestStreak(days: allSummaries)
        let entryCount = rangedEntries.filter { !$0.isCheckIn }.count
        let minutes = Int(rangedLogs.reduce(0) { $0 + $1.minutes }.rounded())
        return HStack(spacing: 10) {
            statTile(value: "\(current)", label: "streak", icon: "flame.fill")
            statTile(value: "\(best)", label: "best", icon: "trophy")
            statTile(value: "\(entryCount)", label: "entries", icon: "text.book.closed")
            statTile(value: "\(minutes)", label: "minutes", icon: "clock")
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Mood

    private struct SentimentPoint: Identifiable {
        let id: Date
        let value: Double
    }

    /// Daily average sentiment mapped onto the 1–5 mood axis so both series
    /// share a scale.
    private var sentimentPoints: [SentimentPoint] {
        let calendar = Calendar.current
        var byDay: [Date: [Double]] = [:]
        for entry in rangedEntries {
            guard let s = entry.sentimentScore else { continue }
            byDay[calendar.startOfDay(for: entry.timestamp), default: []].append(s)
        }
        return byDay.keys.sorted().map { day in
            let scores = byDay[day] ?? []
            let mean = scores.reduce(0, +) / Double(scores.count)
            return SentimentPoint(id: day, value: 1 + (mean + 1) / 2 * 4)
        }
    }

    private var moodChart: some View {
        let moodDays = summaries.filter { $0.averageMood != nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Mood")
                .font(.headline)
            if moodDays.isEmpty {
                Text("No moods recorded in this range — a one-tap check-in is all it takes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(moodDays, id: \.date) { day in
                        LineMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Mood", day.averageMood ?? 3)
                        )
                        .foregroundStyle(palette.mood)
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Mood", day.averageMood ?? 3)
                        )
                        .foregroundStyle(palette.mood)
                        .symbolSize(30)
                    }
                    if showSentiment {
                        ForEach(sentimentPoints) { point in
                            PointMark(
                                x: .value("Day", point.id, unit: .day),
                                y: .value("Writing sentiment", point.value)
                            )
                            .foregroundStyle(palette.minutes.opacity(0.55))
                            .symbol(.diamond)
                            .symbolSize(26)
                        }
                    }
                }
                .chartYScale(domain: 0.5...5.5)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(Mood.emoji(for: v)).font(.caption)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 180)
                Toggle(isOn: $showSentiment) {
                    Text("Show writing sentiment (from your entries, analyzed on-device)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
        .card()
    }

    // MARK: - Score

    private var scoreChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Practice score")
                .font(.headline)
            Chart {
                ForEach(summaries, id: \.date) { day in
                    LineMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Score", day.score)
                    )
                    .foregroundStyle(palette.score)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Score", day.score)
                    )
                    .foregroundStyle(palette.score)
                    .symbolSize(30)
                }
                RuleMark(y: .value("Goal", scoreGoal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("goal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: 0...105)
            .frame(height: 180)
        }
        .card()
    }

    // MARK: - Minutes

    private struct MinuteBar: Identifiable {
        let id = UUID()
        let day: Date
        let activity: String
        let minutes: Double
    }

    private var minuteBars: [MinuteBar] {
        let calendar = Calendar.current
        var byDayAndActivity: [Date: [String: Double]] = [:]
        for log in rangedLogs {
            let day = calendar.startOfDay(for: log.timestamp)
            byDayAndActivity[day, default: [:]][log.activity.name, default: 0] += log.minutes
        }
        return byDayAndActivity.flatMap { day, byActivity in
            byActivity.map { MinuteBar(day: day, activity: $0.key, minutes: $0.value) }
        }
    }

    private var minutesChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity minutes")
                .font(.headline)
            if minuteBars.isEmpty {
                Text("No activities logged in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(minuteBars) { bar in
                    BarMark(
                        x: .value("Day", bar.day, unit: .day),
                        y: .value("Minutes", bar.minutes)
                    )
                    .foregroundStyle(by: .value("Activity", bar.activity))
                }
                .frame(height: 180)
                .chartLegend(position: .bottom, spacing: 8)
            }
        }
        .card()
    }

    // MARK: - Insights

    private var insightsSection: some View {
        // Insights use ALL days, not the chart range — the streak card must
        // agree with the streak stat tile, and mood-lift comparisons only get
        // more trustworthy with the full sample.
        let cards = InsightsEngine.insights(
            days: DayAggregator.summaries(entries: entries, logs: logs), today: .now
        )
        return VStack(alignment: .leading, spacing: 10) {
            Text("Insights")
                .font(.headline)
            if cards.isEmpty {
                Text("Keep logging moods alongside your activities and patterns will start showing up here — like whether meditation days actually feel better.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .card()
            } else {
                ForEach(cards) { insight in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: insight.icon)
                            .font(.title3)
                            .foregroundStyle(palette.score)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(insight.title)
                                .font(.subheadline.weight(.semibold))
                            Text(insight.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .card()
                }
                Text("Patterns, not diagnoses — just your own data, computed on your phone.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
