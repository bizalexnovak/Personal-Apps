import Foundation
import HealthKit

/// One day's worth of read-only Health data, cached alongside the day so a
/// mood entry can sit next to how the person slept and moved. `sleepHours`
/// and `steps` are both optional on purpose: "we don't know" (no read yet,
/// or the read failed) and "zero" (Health genuinely reported none) are
/// different facts and must never be conflated into a false 0.
struct DayHealthSnapshot: Codable, Equatable, Identifiable {
    /// Start of day this snapshot describes.
    var day: Date
    var sleepHours: Double?
    var steps: Int?

    var id: Date { day }

    /// A short human line for the dashboard, e.g. "7h 20m sleep · 6,412 steps".
    /// nil when there's nothing to say at all, so callers can fall back to
    /// their own empty-state copy instead of showing a hollow sentence.
    var summary: String? {
        var parts: [String] = []
        if let sleepHours { parts.append("\(HealthKitReader.hoursText(sleepHours)) sleep") }
        if let steps {
            let formatted = steps.formatted(.number.grouping(.automatic))
            parts.append("\(formatted) steps")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }
}

/// Reads sleep and step data from HealthKit. Strictly read-only: MindLog
/// never writes anything back to Health, and access is soft-asked (opt-in),
/// never required to use the app.
@MainActor
final class HealthKitReader: ObservableObject {
    static let shared = HealthKitReader()

    /// Whether MindLog has been granted (or at least not denied) read access.
    /// HealthKit doesn't expose granted/denied to the reading app for privacy
    /// reasons, so this only reflects that the request completed — actual
    /// data may still come back empty if the person said no.
    @Published private(set) var isAuthorized = false
    @Published private(set) var latest: DayHealthSnapshot?

    /// Key the opt-in `@AppStorage` flag in the view is stored under. Owned
    /// here so the flag's name lives next to the thing it gates.
    static let optInKey = "mindlog_healthkit_optin"

    private let store = HKHealthStore()

    private init() {
        latest = HealthSnapshotStore.load()
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Requests READ-only authorization for sleep and steps. The share set is
    /// intentionally empty — MindLog has no reason to ever write to Health.
    func requestAccess() async -> Bool {
        guard Self.isAvailable else { return false }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let stepsType = HKObjectType.quantityType(forIdentifier: .stepCount)
        else { return false }

        let readTypes: Set<HKObjectType> = [sleepType, stepsType]
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            return true
        } catch {
            isAuthorized = false
            return false
        }
    }

    /// Reads sleep for the night that "belongs to" `day` and step count for
    /// `day` itself, caching the result so it's available the next time the
    /// app opens without another Health round trip.
    @discardableResult
    func snapshot(for day: Date, calendar: Calendar = .current) async -> DayHealthSnapshot {
        let startOfDay = calendar.startOfDay(for: day)
        async let sleep = readSleepHours(for: startOfDay, calendar: calendar)
        async let steps = readStepCount(for: startOfDay, calendar: calendar)
        let snapshot = DayHealthSnapshot(day: startOfDay, sleepHours: await sleep, steps: await steps)
        latest = snapshot
        HealthSnapshotStore.save(snapshot)
        return snapshot
    }

    // MARK: - Sleep

    private func readSleepHours(for day: Date, calendar: Calendar) async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let window = Self.nightWindow(for: day, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(
            withStart: window.start, end: window.end, options: .strictStartDate
        )

        let seconds: [TimeInterval]? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                guard error == nil, let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                ]
                let durations = samples
                    .filter { asleepValues.contains($0.value) }
                    .map { $0.endDate.timeIntervalSince($0.startDate) }
                continuation.resume(returning: durations)
            }
            store.execute(query)
        }

        guard let seconds else { return nil }
        return Self.sleepHours(fromAsleepSeconds: seconds)
    }

    // MARK: - Steps

    private func readStepCount(for day: Date, calendar: Calendar) async -> Int? {
        guard let stepsType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: day, end: endOfDay, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, statistics, error in
                guard error == nil, let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let count = sum.doubleValue(for: .count())
                continuation.resume(returning: Int(count.rounded()))
            }
            store.execute(query)
        }
    }

    // MARK: - Pure helpers (no HealthKit types, so these are unit-testable)

    /// Sums a list of asleep-sample durations (seconds) into total hours.
    /// nil for an empty array — no samples means "unknown", not "zero".
    static func sleepHours(fromAsleepSeconds seconds: [TimeInterval]) -> Double? {
        guard !seconds.isEmpty else { return nil }
        return seconds.reduce(0, +) / 3600
    }

    /// Formats hours as "7h 20m", dropping the hours part entirely under an
    /// hour ("45m") so the summary line never reads "0h 45m".
    static func hoursText(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let wholeHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if wholeHours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(wholeHours)h" }
        return "\(wholeHours)h \(minutes)m"
    }

    /// The night that "belongs to" a day is the one before it: 6 PM the
    /// previous evening through noon on the day itself. Sleep that starts at
    /// 11 PM Tuesday and ends Wednesday morning is Wednesday's sleep, not
    /// Tuesday's — this window captures that without needing to inspect
    /// individual sample boundaries.
    static func nightWindow(for day: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let startOfDay = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay
        let end = calendar.date(byAdding: .hour, value: 12, to: startOfDay) ?? startOfDay
        return (start, end)
    }
}

/// Small JSON-backed cache so the last-read snapshot sits alongside the day
/// in `UserDefaults` without adding a new SwiftData model or migration.
enum HealthSnapshotStore {
    private static let key = "mindlog_health_snapshot"

    static func load() -> DayHealthSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DayHealthSnapshot.self, from: data)
    }

    static func save(_ snapshot: DayHealthSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
