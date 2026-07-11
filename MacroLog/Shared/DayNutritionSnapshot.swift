import Foundation

/// A small, self-contained snapshot of the day's totals + targets, written by
/// the app to a shared App Group container and read by the home-screen widget.
/// Kept deliberately primitive (no SwiftData) so the widget process needs none
/// of the app's model stack.
struct DayNutritionSnapshot: Codable, Equatable {
    var date: Date
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var water: Double
    var calorieTarget: Double
    var proteinTarget: Double
    var carbTarget: Double
    var fatTarget: Double
    var waterTarget: Double

    static let empty = DayNutritionSnapshot(
        date: .now,
        calories: 0, protein: 0, carbs: 0, fat: 0, water: 0,
        calorieTarget: 2000, proteinTarget: 150, carbTarget: 250, fatTarget: 70, waterTarget: 64
    )
}

/// Read/write the snapshot through the shared App Group so the app and the
/// widget see the same data. Update `appGroup` if you change the group ID in
/// the targets' entitlements.
enum WidgetDataStore {
    static let appGroup = "group.com.alexnovak.MacroLog"
    static let widgetKind = "MacroLogTodayWidget"
    private static let key = "day_nutrition_snapshot"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func write(_ snapshot: DayNutritionSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func read() -> DayNutritionSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(DayNutritionSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }
}
