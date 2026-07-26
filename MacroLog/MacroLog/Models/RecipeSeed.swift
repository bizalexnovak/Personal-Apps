import Foundation
import SwiftData

/// The starter recipe library shipped with the app. Seeded once into SwiftData
/// on first launch so the Recipes tab — and the recommender — have something to
/// work with before the user has saved anything of their own. Everything here
/// is an editable estimate: the user can tweak, delete, or add to it freely.
///
/// The set is deliberately spread across meal slots AND macro shapes
/// (protein-heavy, carb-heavy, balanced) so the recommender always has a
/// sensible option whichever way the day's macro gaps lean.
enum RecipeSeed {
    /// A plain description of one seed recipe, resolved into `Recipe` /
    /// `RecipeIngredient` model objects at seed time.
    struct Template {
        let name: String
        let slot: MealSlot
        /// Brief prep steps; empty for assembly-only items (a bar, a parfait)
        /// that need none.
        var instructions: String = ""
        let ingredients: [Ingredient]

        struct Ingredient {
            let name: String
            let quantity: Double
            let unit: String
            let calories: Double
            let protein: Double
            let carbs: Double
            let fat: Double
        }
    }

    static let templates: [Template] = [
        // MARK: Breakfast
        .init(name: "Protein Oatmeal", slot: .breakfast, instructions: "Cook the oats with water or milk (2 min microwave or 5 min stovetop). Stir in the protein powder off the heat, then top with sliced banana and peanut butter.", ingredients: [
            .init(name: "rolled oats", quantity: 0.5, unit: "cup", calories: 150, protein: 5, carbs: 27, fat: 3),
            .init(name: "whey protein", quantity: 1, unit: "scoop", calories: 120, protein: 24, carbs: 3, fat: 2),
            .init(name: "banana", quantity: 1, unit: "medium", calories: 105, protein: 1, carbs: 27, fat: 0),
            .init(name: "peanut butter", quantity: 1, unit: "tbsp", calories: 95, protein: 4, carbs: 3, fat: 8),
        ]),
        .init(name: "Greek Yogurt Parfait", slot: .breakfast, ingredients: [
            .init(name: "nonfat Greek yogurt", quantity: 1, unit: "cup", calories: 130, protein: 22, carbs: 9, fat: 0),
            .init(name: "granola", quantity: 0.25, unit: "cup", calories: 120, protein: 3, carbs: 18, fat: 4),
            .init(name: "mixed berries", quantity: 0.5, unit: "cup", calories: 35, protein: 0, carbs: 9, fat: 0),
        ]),
        .init(name: "Veggie Egg Scramble", slot: .breakfast, instructions: "Whisk the eggs. Wilt the spinach in a nonstick pan over medium heat, pour in the eggs, and scramble gently. Fold in the cheese just before they finish setting.", ingredients: [
            .init(name: "eggs", quantity: 3, unit: "large", calories: 210, protein: 18, carbs: 3, fat: 15),
            .init(name: "spinach", quantity: 1, unit: "cup", calories: 7, protein: 1, carbs: 1, fat: 0),
            .init(name: "cheddar cheese", quantity: 0.25, unit: "cup", calories: 110, protein: 7, carbs: 1, fat: 9),
        ]),
        .init(name: "Avocado Toast & Eggs", slot: .breakfast, instructions: "Toast the bread. Mash the avocado onto it with a pinch of salt. Cook the eggs to taste (fried or scrambled) and put them on top.", ingredients: [
            .init(name: "whole-grain toast", quantity: 2, unit: "slices", calories: 160, protein: 8, carbs: 28, fat: 2),
            .init(name: "avocado", quantity: 0.5, unit: "medium", calories: 120, protein: 1, carbs: 6, fat: 11),
            .init(name: "eggs", quantity: 2, unit: "large", calories: 140, protein: 12, carbs: 1, fat: 10),
        ]),
        .init(name: "Protein Pancakes", slot: .breakfast, instructions: "Whisk the mix, egg, protein powder, and enough water/milk for a pourable batter. Cook on a greased pan over medium heat until bubbles form, then flip and finish.", ingredients: [
            .init(name: "pancake mix", quantity: 0.5, unit: "cup", calories: 180, protein: 5, carbs: 35, fat: 2),
            .init(name: "egg", quantity: 1, unit: "large", calories: 70, protein: 6, carbs: 1, fat: 5),
            .init(name: "whey protein", quantity: 1, unit: "scoop", calories: 120, protein: 24, carbs: 3, fat: 2),
        ]),
        .init(name: "Banana Peanut Butter Toast", slot: .breakfast, ingredients: [
            .init(name: "whole-grain toast", quantity: 2, unit: "slices", calories: 160, protein: 8, carbs: 28, fat: 2),
            .init(name: "peanut butter", quantity: 2, unit: "tbsp", calories: 190, protein: 8, carbs: 6, fat: 16),
            .init(name: "banana", quantity: 1, unit: "medium", calories: 105, protein: 1, carbs: 27, fat: 0),
        ]),

        // MARK: Lunch
        .init(name: "Grilled Chicken Rice Bowl", slot: .lunch, instructions: "Season the chicken and grill or pan-sear about 5-6 min per side to 165°F; rest, then slice. Serve over the rice with steamed broccoli.", ingredients: [
            .init(name: "grilled chicken breast", quantity: 6, unit: "oz", calories: 280, protein: 52, carbs: 0, fat: 6),
            .init(name: "white rice", quantity: 1, unit: "cup", calories: 205, protein: 4, carbs: 45, fat: 0),
            .init(name: "broccoli", quantity: 1, unit: "cup", calories: 55, protein: 4, carbs: 11, fat: 1),
        ]),
        .init(name: "Turkey Avocado Wrap", slot: .lunch, ingredients: [
            .init(name: "flour tortilla", quantity: 1, unit: "large", calories: 190, protein: 5, carbs: 32, fat: 5),
            .init(name: "sliced turkey breast", quantity: 4, unit: "oz", calories: 120, protein: 24, carbs: 2, fat: 2),
            .init(name: "avocado", quantity: 0.5, unit: "medium", calories: 120, protein: 1, carbs: 6, fat: 11),
        ]),
        .init(name: "Tuna Salad Sandwich", slot: .lunch, instructions: "Drain the tuna and mix with the mayo (salt, pepper, a squeeze of lemon if you like). Spread between the bread slices.", ingredients: [
            .init(name: "whole-grain bread", quantity: 2, unit: "slices", calories: 160, protein: 8, carbs: 28, fat: 2),
            .init(name: "canned tuna", quantity: 1, unit: "can", calories: 100, protein: 22, carbs: 0, fat: 1),
            .init(name: "mayonnaise", quantity: 1, unit: "tbsp", calories: 90, protein: 0, carbs: 0, fat: 10),
        ]),
        .init(name: "Chicken Caesar Salad", slot: .lunch, ingredients: [
            .init(name: "grilled chicken breast", quantity: 5, unit: "oz", calories: 230, protein: 43, carbs: 0, fat: 5),
            .init(name: "romaine lettuce", quantity: 2, unit: "cups", calories: 20, protein: 1, carbs: 4, fat: 0),
            .init(name: "Caesar dressing", quantity: 2, unit: "tbsp", calories: 160, protein: 1, carbs: 2, fat: 17),
            .init(name: "parmesan", quantity: 2, unit: "tbsp", calories: 45, protein: 4, carbs: 0, fat: 3),
        ]),
        .init(name: "Burrito Bowl", slot: .lunch, ingredients: [
            .init(name: "white rice", quantity: 1, unit: "cup", calories: 205, protein: 4, carbs: 45, fat: 0),
            .init(name: "black beans", quantity: 0.5, unit: "cup", calories: 110, protein: 7, carbs: 20, fat: 0),
            .init(name: "grilled chicken breast", quantity: 4, unit: "oz", calories: 185, protein: 35, carbs: 0, fat: 4),
            .init(name: "salsa", quantity: 0.25, unit: "cup", calories: 20, protein: 1, carbs: 4, fat: 0),
        ]),
        .init(name: "Quinoa Veggie Bowl", slot: .lunch, instructions: "Rinse and simmer the quinoa (1 part quinoa to 2 parts water, ~15 min). Roast or saute the vegetables, then bowl everything with the chickpeas.", ingredients: [
            .init(name: "quinoa", quantity: 1, unit: "cup", calories: 220, protein: 8, carbs: 39, fat: 4),
            .init(name: "chickpeas", quantity: 0.5, unit: "cup", calories: 135, protein: 7, carbs: 22, fat: 2),
            .init(name: "roasted vegetables", quantity: 1, unit: "cup", calories: 80, protein: 3, carbs: 14, fat: 2),
        ]),

        // MARK: Dinner
        .init(name: "Salmon with Sweet Potato", slot: .dinner, instructions: "Roast the sweet potato at 400°F for ~40 min. Season the salmon and roast or pan-sear ~4 min per side. Steam or roast the asparagus alongside.", ingredients: [
            .init(name: "salmon fillet", quantity: 6, unit: "oz", calories: 350, protein: 34, carbs: 0, fat: 22),
            .init(name: "sweet potato", quantity: 1, unit: "medium", calories: 110, protein: 2, carbs: 26, fat: 0),
            .init(name: "asparagus", quantity: 1, unit: "cup", calories: 40, protein: 4, carbs: 7, fat: 0),
        ]),
        .init(name: "Beef & Broccoli Stir-Fry", slot: .dinner, instructions: "Slice the steak thin against the grain. Stir-fry on high heat 2-3 min, add the broccoli with a splash of soy sauce, and cook until crisp-tender. Serve over rice.", ingredients: [
            .init(name: "flank steak", quantity: 6, unit: "oz", calories: 340, protein: 48, carbs: 0, fat: 16),
            .init(name: "broccoli", quantity: 1.5, unit: "cups", calories: 80, protein: 6, carbs: 16, fat: 1),
            .init(name: "white rice", quantity: 1, unit: "cup", calories: 205, protein: 4, carbs: 45, fat: 0),
        ]),
        .init(name: "Spaghetti with Meat Sauce", slot: .dinner, instructions: "Boil the spaghetti per the package. Brown the beef, drain, and simmer with the marinara for 10 min. Toss with the pasta.", ingredients: [
            .init(name: "spaghetti", quantity: 2, unit: "oz dry", calories: 200, protein: 7, carbs: 42, fat: 1),
            .init(name: "ground beef", quantity: 4, unit: "oz", calories: 290, protein: 28, carbs: 0, fat: 20),
            .init(name: "marinara sauce", quantity: 0.5, unit: "cup", calories: 70, protein: 2, carbs: 12, fat: 2),
        ]),
        .init(name: "Grilled Chicken & Veg", slot: .dinner, instructions: "Season the chicken and grill or pan-sear 5-6 min per side to 165°F. Toss the vegetables in the olive oil and roast at 425°F for ~20 min.", ingredients: [
            .init(name: "grilled chicken breast", quantity: 7, unit: "oz", calories: 325, protein: 61, carbs: 0, fat: 7),
            .init(name: "mixed vegetables", quantity: 1.5, unit: "cups", calories: 90, protein: 4, carbs: 18, fat: 1),
            .init(name: "olive oil", quantity: 1, unit: "tbsp", calories: 120, protein: 0, carbs: 0, fat: 14),
        ]),
        .init(name: "Turkey Chili", slot: .dinner, instructions: "Brown the turkey in a pot. Add the beans and tomatoes with chili powder and cumin, then simmer at least 20 min, stirring occasionally.", ingredients: [
            .init(name: "ground turkey", quantity: 5, unit: "oz", calories: 240, protein: 34, carbs: 0, fat: 12),
            .init(name: "kidney beans", quantity: 0.75, unit: "cup", calories: 165, protein: 11, carbs: 30, fat: 0),
            .init(name: "diced tomatoes", quantity: 0.5, unit: "cup", calories: 25, protein: 1, carbs: 6, fat: 0),
        ]),
        .init(name: "Shrimp Tacos", slot: .dinner, instructions: "Season the shrimp (chili powder, lime) and sear 1-2 min per side. Warm the tortillas and fill with the shrimp and slaw.", ingredients: [
            .init(name: "corn tortillas", quantity: 3, unit: "small", calories: 150, protein: 4, carbs: 30, fat: 2),
            .init(name: "shrimp", quantity: 6, unit: "oz", calories: 170, protein: 34, carbs: 0, fat: 2),
            .init(name: "cabbage slaw", quantity: 1, unit: "cup", calories: 60, protein: 1, carbs: 6, fat: 4),
        ]),

        // MARK: Snacks
        .init(name: "Apple & Peanut Butter", slot: .snack, ingredients: [
            .init(name: "apple", quantity: 1, unit: "medium", calories: 95, protein: 0, carbs: 25, fat: 0),
            .init(name: "peanut butter", quantity: 2, unit: "tbsp", calories: 190, protein: 8, carbs: 6, fat: 16),
        ]),
        .init(name: "Cottage Cheese & Pineapple", slot: .snack, ingredients: [
            .init(name: "low-fat cottage cheese", quantity: 1, unit: "cup", calories: 180, protein: 24, carbs: 8, fat: 5),
            .init(name: "pineapple", quantity: 0.5, unit: "cup", calories: 40, protein: 0, carbs: 11, fat: 0),
        ]),
        .init(name: "Protein Shake", slot: .snack, ingredients: [
            .init(name: "whey protein", quantity: 1, unit: "scoop", calories: 120, protein: 24, carbs: 3, fat: 2),
            .init(name: "milk", quantity: 1, unit: "cup", calories: 120, protein: 8, carbs: 12, fat: 5),
        ]),
        .init(name: "Trail Mix", slot: .snack, ingredients: [
            .init(name: "mixed nuts", quantity: 0.25, unit: "cup", calories: 200, protein: 6, carbs: 8, fat: 17),
            .init(name: "raisins", quantity: 2, unit: "tbsp", calories: 60, protein: 0, carbs: 16, fat: 0),
        ]),
        .init(name: "Hummus & Veggies", slot: .snack, ingredients: [
            .init(name: "hummus", quantity: 0.25, unit: "cup", calories: 100, protein: 5, carbs: 9, fat: 6),
            .init(name: "baby carrots", quantity: 1, unit: "cup", calories: 50, protein: 1, carbs: 12, fat: 0),
        ]),
        .init(name: "Protein Bar", slot: .snack, ingredients: [
            .init(name: "protein bar", quantity: 1, unit: "bar", calories: 210, protein: 20, carbs: 22, fat: 7),
        ]),
    ]

    private static let seededFlag = "recipes_seeded_v1"
    private static let instructionsBackfillFlag = "recipes_instructions_backfilled_v1"

    /// Insert the starter library once. Guarded by a UserDefaults flag so it
    /// never duplicates on later launches (and never fights the user if they
    /// delete a seeded recipe). Existing user recipes are left untouched.
    @MainActor
    static func seedIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        if !defaults.bool(forKey: seededFlag) {
            for recipe in build() {
                context.insert(recipe)
            }
            try? context.save()
            defaults.set(true, forKey: seededFlag)
        }
        backfillInstructionsIfNeeded(in: context, defaults: defaults)
    }

    /// One-time repair for installs seeded before instructions existed: any
    /// recipe still matching a template's name and carrying no instructions
    /// gets the template's steps. Renamed or user-authored recipes (and any
    /// the user wrote steps for) are untouched.
    @MainActor
    static func backfillInstructionsIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: instructionsBackfillFlag) else { return }
        defaults.set(true, forKey: instructionsBackfillFlag)
        let byName = Dictionary(
            templates.map { ($0.name, $0.instructions) },
            uniquingKeysWith: { first, _ in first }
        )
        guard let recipes = try? context.fetch(FetchDescriptor<Recipe>()) else { return }
        var changed = false
        for recipe in recipes where recipe.instructions.isEmpty {
            if let steps = byName[recipe.name], !steps.isEmpty {
                recipe.instructions = steps
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// Materialize the templates into model objects (used by the seeder and by
    /// tests). Ingredients carry stable sort order and high confidence — these
    /// are curated known values, not machine estimates that need a second look.
    static func build() -> [Recipe] {
        templates.map { template in
            let ingredients = template.ingredients.enumerated().map { index, ing in
                RecipeIngredient(
                    name: ing.name, quantity: ing.quantity, unit: ing.unit,
                    calories: ing.calories, protein: ing.protein,
                    carbs: ing.carbs, fat: ing.fat,
                    matchConfidence: MatchConfidence.high,
                    sortOrder: index
                )
            }
            return Recipe(
                name: template.name, mealSlot: template.slot,
                instructions: template.instructions, ingredients: ingredients
            )
        }
    }
}
