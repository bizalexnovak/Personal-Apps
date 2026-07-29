import SwiftUI
import SwiftData

/// A practice session about to run: either a guided breathing pattern or a
/// silent meditation timer. Drives the fullScreenCover.
struct PracticeSession: Identifiable {
    let id = UUID()
    /// nil = meditation timer.
    var pattern: BreathingPattern?
    var duration: Double
}

/// The Practice tab: do something good for your head, then have it logged
/// automatically. Guided breathing and a meditation timer run in-app and log
/// themselves on completion; everything else (a walk, a call, therapy) is a
/// two-tap manual log.
struct PracticeView: View {
    @Environment(\.appAccent) private var accent
    @Environment(\.appBackground) private var appBackground
    @EnvironmentObject private var hub: AppHub

    @Query(sort: \ActivityLog.timestamp, order: .reverse) private var logs: [ActivityLog]

    @State private var session: PracticeSession?
    @State private var loggingActivity: WellbeingActivity?
    @State private var showActivityPicker = false

    private var todayMinutes: Double {
        let calendar = Calendar.current
        return logs
            .filter { calendar.isDateInToday($0.timestamp) }
            .reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    breathingSection
                    meditationSection
                    logSection
                }
                .padding()
            }
            .appBackground(appBackground)
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(item: $session) { session in
            if let pattern = session.pattern {
                BreathingSessionView(pattern: pattern, duration: session.duration)
            } else {
                MeditationTimerView(duration: session.duration)
            }
        }
        .sheet(item: $loggingActivity) { activity in
            ActivityLogSheet(day: Calendar.current.startOfDay(for: .now), activity: activity)
        }
        .sheet(isPresented: $showActivityPicker) {
            ActivityLogSheet(day: Calendar.current.startOfDay(for: .now))
        }
        .onChange(of: hub.pendingPracticeAction) { _, action in
            consume(action)
        }
        .onAppear { consume(hub.pendingPracticeAction) }
    }

    private func consume(_ action: AppHub.PracticeAction?) {
        guard let action else { return }
        hub.pendingPracticeAction = nil
        switch action {
        case .breathe: session = PracticeSession(pattern: .box, duration: 180)
        case .meditate: session = PracticeSession(pattern: nil, duration: 600)
        case .logActivity: showActivityPicker = true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(accent)
            Text(todayMinutes > 0
                 ? "\(Int(todayMinutes.rounded())) minutes practiced today"
                 : "No practice yet today — one minute of breathing counts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Guided breathing

    private var breathingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Guided breathing")
                .font(.headline)
            ForEach(BreathingPattern.all) { pattern in
                Menu {
                    ForEach([1.0, 2, 3, 5, 10], id: \.self) { minutes in
                        Button("\(Int(minutes)) minute\(minutes == 1 ? "" : "s")") {
                            session = PracticeSession(pattern: pattern, duration: minutes * 60)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "wind")
                            .font(.title3)
                            .foregroundStyle(accent)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pattern.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(pattern.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(accent)
                    }
                    .contentShape(Rectangle())
                }
                .card()
            }
        }
    }

    // MARK: - Meditation

    private var meditationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meditation timer")
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                Text("Silent timer with a start and finish cue. The screen stays awake; minutes log themselves.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach([2.0, 5, 10, 15, 20, 30], id: \.self) { minutes in
                        Button {
                            session = PracticeSession(pattern: nil, duration: minutes * 60)
                        } label: {
                            Text("\(Int(minutes)) min")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .card()
        }
    }

    // MARK: - Manual logging

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log an activity")
                .font(.headline)
            Text("Anything you did for your mind today — it all feeds your practice score.")
                .font(.caption)
                .foregroundStyle(.secondary)
            let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ActivityCatalog.all) { activity in
                    Button {
                        loggingActivity = activity
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: activity.icon)
                                .font(.title3)
                                .foregroundStyle(accent)
                            Text(activity.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.quaternary, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Log-an-activity sheet. Opened with an activity pre-picked (Practice grid)
/// or without one (Home / quick menu), in which case a picker grid comes
/// first. Duration starts from the activity's presets with a custom field.
struct ActivityLogSheet: View {
    /// The day the log lands on (Home passes its selected day, so backfilling
    /// yesterday works). Time-of-day: now for today, midday for past days.
    var day: Date
    var activity: WellbeingActivity?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent

    @State private var selected: WellbeingActivity?
    @State private var minutes: Double = 0
    @State private var customMinutes = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Group {
                if let chosen = selected {
                    form(for: chosen)
                } else {
                    picker
                }
            }
            .navigationTitle(selected.map(\.name) ?? "Log an activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if selected != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(finalMinutes <= 0)
                    }
                }
            }
        }
        .onAppear {
            if selected == nil { selected = activity }
        }
        .presentationDetents([.medium, .large])
    }

    private var picker: some View {
        ScrollView {
            let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ActivityCatalog.all) { activity in
                    Button {
                        selected = activity
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: activity.icon)
                                .font(.title3)
                                .foregroundStyle(accent)
                            Text(activity.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private func form(for activity: WellbeingActivity) -> some View {
        Form {
            if !activity.why.isEmpty {
                Section {
                    Label(activity.why, systemImage: activity.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section("How long?") {
                let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(activity.presetMinutes, id: \.self) { preset in
                        Button {
                            minutes = preset
                            customMinutes = ""
                        } label: {
                            Text("\(Int(preset))")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    (minutes == preset && customMinutes.isEmpty)
                                        ? accent.opacity(0.25) : accent.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("Custom")
                    TextField("minutes", text: $customMinutes)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section("Note (optional)") {
                TextField("e.g. morning walk by the river", text: $note, axis: .vertical)
            }
        }
        .keyboardDismissBar()
    }

    private var finalMinutes: Double {
        if let custom = Double(customMinutes.trimmingCharacters(in: .whitespaces)), custom > 0 {
            return custom
        }
        return minutes
    }

    private func save() {
        guard let activity = selected, finalMinutes > 0 else { return }
        let calendar = Calendar.current
        let timestamp: Date
        if calendar.isDateInToday(day) {
            timestamp = .now
        } else {
            timestamp = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }
        context.insert(ActivityLog(
            timestamp: timestamp,
            activityID: activity.id,
            minutes: finalMinutes,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        dismiss()
    }
}
