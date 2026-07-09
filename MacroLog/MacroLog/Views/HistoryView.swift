import SwiftUI
import SwiftData

/// Every day you've logged, newest first, with that day's totals. Tap a day to
/// see its meals.
struct HistoryView: View {
    @Query(sort: \Meal.timestamp, order: .reverse) private var meals: [Meal]

    /// Meals grouped by calendar day, newest day first.
    private var days: [(date: Date, meals: [Meal])] {
        let grouped = Dictionary(grouping: meals) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped
            .map { (date: $0.key, meals: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if days.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "calendar",
                        description: Text("Days you log meals will show up here.")
                    )
                }
                ForEach(days, id: \.date) { day in
                    NavigationLink {
                        DayDetailView(date: day.date, meals: day.meals)
                    } label: {
                        DayRow(date: day.date, meals: day.meals)
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

private struct DayRow: View {
    let date: Date
    let meals: [Meal]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)
            HStack(spacing: 10) {
                Text("\(Int(meals.reduce(0) { $0 + $1.totalCalories }.rounded())) kcal")
                Text("P \(Int(meals.reduce(0) { $0 + $1.totalProtein }.rounded()))")
                Text("C \(Int(meals.reduce(0) { $0 + $1.totalCarbs }.rounded()))")
                Text("F \(Int(meals.reduce(0) { $0 + $1.totalFat }.rounded()))")
                Label("\(Int(meals.reduce(0) { $0 + $1.waterOunces }.rounded())) oz", systemImage: "drop.fill")
                    .foregroundStyle(.cyan)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// One day's meals with a totals header. Meals are editable and deletable,
/// same as Today's list.
private struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let date: Date
    let meals: [Meal]

    private var sortedMeals: [Meal] {
        meals.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        List {
            Section("Totals") {
                totalRow("Calories", meals.reduce(0) { $0 + $1.totalCalories }, "kcal")
                totalRow("Protein", meals.reduce(0) { $0 + $1.totalProtein }, "g")
                totalRow("Carbs", meals.reduce(0) { $0 + $1.totalCarbs }, "g")
                totalRow("Fat", meals.reduce(0) { $0 + $1.totalFat }, "g")
                totalRow("Water", meals.reduce(0) { $0 + $1.waterOunces }, "oz")
            }
            Section("Meals") {
                ForEach(sortedMeals) { meal in
                    NavigationLink {
                        EditMealView(meal: meal)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.displayName)
                                .lineLimit(2)
                            Text("\(Int(meal.totalCalories.rounded())) kcal · \(meal.timestamp, format: .dateTime.hour().minute())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(sortedMeals[index])
                    }
                }
            }
        }
        .navigationTitle(Text(date, format: .dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func totalRow(_ label: String, _ value: Double, _ unit: String) -> some View {
        LabeledContent(label) {
            Text("\(Int(value.rounded())) \(unit)")
                .monospacedDigit()
        }
    }
}
