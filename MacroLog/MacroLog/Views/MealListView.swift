import SwiftUI
import SwiftData

struct MealListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: MealCaptureCoordinator
    @Query(sort: \Meal.timestamp, order: .reverse) private var meals: [Meal]

    @State private var mealText = ""

    private var todaysMeals: [Meal] {
        meals.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Describe what you ate…", text: $mealText, axis: .vertical)
                            .disabled(coordinator.isCapturing)
                        if coordinator.isWorking {
                            ProgressView()
                        } else {
                            Button {
                                let text = mealText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !text.isEmpty else { return }
                                mealText = ""
                                Task { await coordinator.begin(text: text, in: modelContext) }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                            }
                            .disabled(
                                mealText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || coordinator.isCapturing
                            )
                        }
                    }
                }

                Section("Today") {
                    if todaysMeals.isEmpty {
                        Text("No meals logged today.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(todaysMeals) { meal in
                        MealRow(meal: meal)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(todaysMeals[index])
                        }
                    }
                }
            }
            .navigationTitle("Meals")
        }
    }
}

/// One meal in the list: tap to expand and see the parsed items, with a link
/// through to the edit screen.
private struct MealRow: View {
    let meal: Meal
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(meal.items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                        Text("\(item.quantity.formatted()) \(item.unit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(item.calories.rounded())) kcal")
                        .font(.subheadline.monospacedDigit())
                    if item.matchConfidence == MatchConfidence.low {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Needs review")
                    }
                }
            }
            NavigationLink("Edit meal") {
                EditMealView(meal: meal)
            }
            .font(.subheadline)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.rawText)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(meal.timestamp, format: .dateTime.hour().minute())
                    Text("\(Int(meal.totalCalories.rounded())) kcal")
                    Text("P \(Int(meal.totalProtein.rounded())) · C \(Int(meal.totalCarbs.rounded())) · F \(Int(meal.totalFat.rounded()))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
