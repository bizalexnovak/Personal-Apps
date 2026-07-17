import SwiftUI
import SwiftData

/// The Recipes tab: saved meal templates you can re-log with one tap. Create a
/// recipe here from scratch, or save any logged meal as a recipe from the meal
/// editor on the Today tab.
struct RecipesView: View {
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackground) private var appBackground

    @State private var showNamePrompt = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if recipes.isEmpty {
                    ContentUnavailableView(
                        "No recipes yet",
                        systemImage: "book",
                        description: Text("Create one with the + button, or open a meal on the Today tab and tap \u{201C}Save as recipe\u{201D}.")
                    )
                } else {
                    ForEach(recipes) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            recipeRow(recipe)
                        }
                    }
                    .onDelete(perform: deleteRecipes)
                }
            }
            .appBackground(appBackground)
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; showNamePrompt = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New recipe")
                }
            }
            .alert("New recipe", isPresented: $showNamePrompt) {
                TextField("Name", text: $newName)
                Button("Create") { createRecipe() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Name it, then add the ingredients.")
            }
        }
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recipe.name)
            Text("\(recipe.ingredients.count) ingredient\(recipe.ingredients.count == 1 ? "" : "s") · \(Int(recipe.totalCalories.rounded())) kcal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func createRecipe() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Recipe(name: trimmed))
        try? modelContext.save()
    }

    private func deleteRecipes(_ offsets: IndexSet) {
        // Capture the targets before deleting — removing from a live @Query
        // array while indexing into it risks hitting shifted indices.
        let targets = offsets.map { recipes[$0] }
        for recipe in targets {
            modelContext.delete(recipe)
        }
    }
}

/// One recipe: rename it, manage its ingredients, and log it as a meal.
struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackground) private var appBackground

    @State private var showIngredientEditor = false
    @State private var justLogged = false

    var body: some View {
        List {
            Section("Name") {
                TextField("Recipe name", text: $recipe.name)
            }

            Section {
                ForEach(recipe.sortedIngredients) { ingredient in
                    ingredientRow(ingredient)
                }
                .onDelete(perform: deleteIngredients)
                Button {
                    showIngredientEditor = true
                } label: {
                    Label("Add ingredient", systemImage: "plus")
                }
            } header: {
                Text("Ingredients")
            } footer: {
                if !recipe.ingredients.isEmpty {
                    Text("Total: \(Int(recipe.totalCalories.rounded())) kcal · P \(Int(recipe.totalProtein.rounded()))g · C \(Int(recipe.totalCarbs.rounded()))g · F \(Int(recipe.totalFat.rounded()))g")
                }
            }

            Section {
                Button {
                    logAsMeal()
                } label: {
                    Label(
                        justLogged ? "Added to today" : "Log this recipe today",
                        systemImage: justLogged ? "checkmark.circle.fill" : "plus.square.on.square"
                    )
                }
                .disabled(justLogged || recipe.ingredients.isEmpty)
            } footer: {
                Text("Adds the whole recipe to today's diary as a meal.")
            }
        }
        .keyboardDismissBar()
        .appBackground(appBackground)
        .navigationTitle(recipe.name.isEmpty ? "Recipe" : recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showIngredientEditor) {
            IngredientEditorView { ingredient in
                ingredient.sortOrder = recipe.nextSortOrder
                // Insert explicitly before wiring the relationship — relying
                // on relationship-cascade insert for an object appended to an
                // already-persisted parent is flaky on some SwiftData builds.
                modelContext.insert(ingredient)
                recipe.ingredients.append(ingredient)
                try? modelContext.save()
            }
        }
    }

    private func ingredientRow(_ ingredient: RecipeIngredient) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ingredient.name)
            Text("\(ingredient.quantity.formatted()) \(ingredient.unit) · \(Int(ingredient.calories.rounded())) kcal · P \(Int(ingredient.protein.rounded()))g · C \(Int(ingredient.carbs.rounded()))g · F \(Int(ingredient.fat.rounded()))g")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func deleteIngredients(_ offsets: IndexSet) {
        // Offsets are positions in the SORTED array the ForEach displays —
        // resolve against the same ordering, captured before any deletion.
        let sorted = recipe.sortedIngredients
        let targets = offsets.map { sorted[$0] }
        for ingredient in targets {
            modelContext.delete(ingredient)
        }
    }

    private func logAsMeal() {
        modelContext.insert(recipe.makeMeal())
        try? modelContext.save()
        justLogged = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justLogged = false
        }
    }
}

/// Manual entry for one recipe ingredient: name, portion, and macros.
private struct IngredientEditorView: View {
    var onSave: (RecipeIngredient) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var quantity = 1.0
    @State private var unit = "serving"
    @State private var calories = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredient") {
                    TextField("Name", text: $name)
                    HStack {
                        TextField("Quantity", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 80)
                        TextField("Unit", text: $unit)
                    }
                }
                Section("Macros") {
                    LabeledContent("Calories (kcal)") {
                        TextField("kcal", value: $calories, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Protein (g)") {
                        TextField("g", value: $protein, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Carbs (g)") {
                        TextField("g", value: $carbs, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Fat (g)") {
                        TextField("g", value: $fat, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .keyboardDismissBar()
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(RecipeIngredient(
                            name: name.trimmingCharacters(in: .whitespaces),
                            quantity: quantity, unit: unit,
                            calories: calories, protein: protein,
                            carbs: carbs, fat: fat
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
