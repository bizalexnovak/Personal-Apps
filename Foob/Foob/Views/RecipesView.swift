import SwiftUI
import SwiftData

/// The Recipes tab: saved meal templates you can re-log with one tap. Create a
/// recipe here from scratch, or save any logged meal as a recipe from the meal
/// editor on the Today tab.
struct RecipesView: View {
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \Meal.timestamp, order: .reverse) private var meals: [Meal]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackground) private var appBackground

    @AppStorage(TargetKeys.calories) private var calorieTarget = 2000.0
    @AppStorage(TargetKeys.protein) private var proteinTarget = 150.0
    @AppStorage(TargetKeys.carbs) private var carbTarget = 250.0
    @AppStorage(TargetKeys.fat) private var fatTarget = 70.0

    @State private var showNamePrompt = false
    @State private var newName = ""
    @State private var showSearch = false
    /// Briefly flags the recipe just quick-logged, for the checkmark feedback.
    @State private var justLoggedID: UUID?
    /// Recomputed each time the tab is shown / data changes so the "now"
    /// window and macro gaps stay current without churning on every render.
    @State private var recommendations: [RecipeRecommendation] = []

    var body: some View {
        NavigationStack {
            List {
                if !recommendations.isEmpty {
                    Section {
                        ForEach(recommendations) { rec in
                            recommendationRow(rec)
                        }
                    } header: {
                        Text("Recommended for now")
                    } footer: {
                        Text("Ranked by time of day, how far you are from today\u{2019}s macro goals, and what you log most.")
                    }
                }

                Section {
                    if recipes.isEmpty {
                        ContentUnavailableView(
                            "No recipes yet",
                            systemImage: "book",
                            description: Text("Create one with the + button, search the web with the magnifying glass, or open a meal on the Today tab and tap \u{201C}Save as recipe\u{201D}.")
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
                } header: {
                    if !recipes.isEmpty { Text("All recipes") }
                }
            }
            .appBackground(appBackground)
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search recipes online")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; showNamePrompt = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New recipe")
                }
            }
            .sheet(isPresented: $showSearch) {
                RecipeSearchView()
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
        .onAppear(perform: refreshRecommendations)
        // Re-rank when a meal is logged (macro gaps shift) or recipes change.
        .onChange(of: meals) { _, _ in refreshRecommendations() }
        .onChange(of: recipes) { _, _ in refreshRecommendations() }
    }

    private func refreshRecommendations() {
        let calendar = Calendar.current
        var intake = DayIntake.none
        for meal in meals where calendar.isDateInToday(meal.timestamp) {
            let t = meal.totals
            intake.calories += t.calories
            intake.protein += t.protein
            intake.carbs += t.carbs
            intake.fat += t.fat
        }
        let targets = MacroTargets(
            calories: calorieTarget, protein: proteinTarget,
            carbs: carbTarget, fat: fatTarget
        )
        recommendations = RecipeRecommender.recommend(
            recipes: recipes, targets: targets, intake: intake, limit: 4
        )
    }

    private func recommendationRow(_ rec: RecipeRecommendation) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                RecipeDetailView(recipe: rec.recipe)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rec.recipe.name)
                    Text(rec.reason)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary.opacity(0.6)))
                    Text("\(Int(rec.recipe.totalCalories.rounded())) kcal · P \(Int(rec.recipe.totalProtein.rounded()))g · C \(Int(rec.recipe.totalCarbs.rounded()))g · F \(Int(rec.recipe.totalFat.rounded()))g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                quickLog(rec.recipe)
            } label: {
                Image(systemName: justLoggedID == rec.recipe.id ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(justLoggedID == rec.recipe.id ? Color.green : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Log \(rec.recipe.name) now")
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

    /// Log a recommended recipe straight to today and record the preference so
    /// the recommender learns from it.
    private func quickLog(_ recipe: Recipe) {
        recipe.recordLogged()
        modelContext.insert(recipe.makeMeal())
        try? modelContext.save()
        withAnimation { justLoggedID = recipe.id }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { justLoggedID = nil }
            refreshRecommendations() // reflect the new intake in the ranking
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
    @State private var shareState: ShareState = .idle

    enum ShareState { case idle, sharing, shared, failed }

    var body: some View {
        List {
            Section("Name") {
                TextField("Recipe name", text: $recipe.name)
            }

            Section {
                Picker("Best for", selection: Binding(
                    get: { recipe.slot },
                    set: { recipe.slot = $0 }
                )) {
                    ForEach(MealSlot.allCases, id: \.self) { slot in
                        Text(slot.label).tag(slot)
                    }
                }
            } footer: {
                Text("When this recipe fits — used to time recommendations.")
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
                TextField(
                    "Optional — steps for making it",
                    text: $recipe.instructions,
                    axis: .vertical
                )
                .lineLimit(2...14)
            } header: {
                Text("Instructions")
            } footer: {
                if recipe.instructions.isEmpty {
                    Text("Leave empty for things that need no prep (a bar, a fast-food item).")
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

                // Only invite-code installs have a shared server to publish to.
                if ClaudeEndpoint.proxyConfig != nil {
                    Button {
                        share()
                    } label: {
                        switch shareState {
                        case .idle: Label("Share to community", systemImage: "square.and.arrow.up")
                        case .sharing: HStack { ProgressView(); Text("Sharing…") }
                        case .shared: Label("Shared", systemImage: "checkmark.circle.fill")
                        case .failed: Label("Couldn't share — tap to retry", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(shareState == .sharing || shareState == .shared || recipe.ingredients.isEmpty)
                }
            } footer: {
                Text(ClaudeEndpoint.proxyConfig != nil
                    ? "\u{201C}Log\u{201D} adds the recipe to today's diary. \u{201C}Share\u{201D} publishes it to the community library other users can search."
                    : "Adds the whole recipe to today's diary as a meal.")
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
        recipe.recordLogged()
        modelContext.insert(recipe.makeMeal())
        try? modelContext.save()
        justLogged = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justLogged = false
        }
    }

    private func share() {
        shareState = .sharing
        Task {
            shareState = await CommunitySync.shareRecipe(recipe) ? .shared : .failed
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
