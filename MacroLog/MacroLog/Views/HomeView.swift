import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var meals: [Meal]

    @AppStorage(TargetKeys.calories) private var calorieTarget = 2000.0
    @AppStorage(TargetKeys.protein) private var proteinTarget = 150.0
    @AppStorage(TargetKeys.carbs) private var carbTarget = 250.0
    @AppStorage(TargetKeys.fat) private var fatTarget = 70.0

    private var todaysMeals: [Meal] {
        meals.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MacroProgressRow(
                        label: "Calories", unit: "kcal", color: .orange,
                        value: todaysMeals.reduce(0) { $0 + $1.totalCalories },
                        target: calorieTarget
                    )
                    MacroProgressRow(
                        label: "Protein", unit: "g", color: .red,
                        value: todaysMeals.reduce(0) { $0 + $1.totalProtein },
                        target: proteinTarget
                    )
                    MacroProgressRow(
                        label: "Carbs", unit: "g", color: .blue,
                        value: todaysMeals.reduce(0) { $0 + $1.totalCarbs },
                        target: carbTarget
                    )
                    MacroProgressRow(
                        label: "Fat", unit: "g", color: .yellow,
                        value: todaysMeals.reduce(0) { $0 + $1.totalFat },
                        target: fatTarget
                    )
                } header: {
                    Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                }

                if todaysMeals.isEmpty {
                    ContentUnavailableView(
                        "Nothing logged today",
                        systemImage: "fork.knife",
                        description: Text("Say \u{201C}Log meal in MacroLog\u{201D} to Siri, or add a meal from the Meals tab.")
                    )
                } else {
                    Section("Today's meals") {
                        ForEach(todaysMeals.sorted { $0.timestamp > $1.timestamp }) { meal in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.rawText)
                                    .lineLimit(1)
                                Text("\(Int(meal.totalCalories.rounded())) kcal · \(meal.timestamp, format: .dateTime.hour().minute())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today")
        }
    }
}

private struct MacroProgressRow: View {
    let label: String
    let unit: String
    let color: Color
    let value: Double
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(target.rounded())) \(unit)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: target > 0 ? min(value / target, 1) : 0)
                .tint(color)
        }
        .padding(.vertical, 4)
    }
}
