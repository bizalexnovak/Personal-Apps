import XCTest
@testable import MacroLog

final class MealSlotTests: XCTestCase {
    func testHourMapsToSlot() {
        XCTAssertEqual(MealSlot.current(hour: 8), .breakfast)
        XCTAssertEqual(MealSlot.current(hour: 12), .lunch)
        XCTAssertEqual(MealSlot.current(hour: 19), .dinner)
        XCTAssertEqual(MealSlot.current(hour: 16), .snack) // mid-afternoon gap
        XCTAssertEqual(MealSlot.current(hour: 23), .snack) // late night
    }
}

final class RecipeRecommenderTests: XCTestCase {
    private let targets = MacroTargets(calories: 2000, protein: 150, carbs: 250, fat: 70)

    private func at(hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 17; comps.hour = hour
        return Calendar.current.date(from: comps)!
    }

    private func recipe(_ name: String, slot: MealSlot, p: Double, c: Double, f: Double) -> Recipe {
        Recipe(name: name, mealSlot: slot, ingredients: [
            RecipeIngredient(name: name, quantity: 1, unit: "serving",
                             calories: p * 4 + c * 4 + f * 9, protein: p, carbs: c, fat: f)
        ])
    }

    func testStartOfDayLeansOnTimeOfDay() {
        // No intake yet → macro term is uniform, so time of day decides.
        let breakfast = recipe("Oatmeal", slot: .breakfast, p: 10, c: 40, f: 5)
        let dinner = recipe("Steak", slot: .dinner, p: 50, c: 0, f: 20)
        let recs = RecipeRecommender.recommend(
            recipes: [dinner, breakfast], targets: targets,
            intake: .none, now: at(hour: 8)
        )
        XCTAssertEqual(recs.first?.recipe.name, "Oatmeal")
    }

    func testProteinGapPromotesProteinHeavyRecipe() {
        // Carbs and fat are near goal; protein is far — so a protein-heavy
        // recipe should outrank a carb-heavy one at the same meal time.
        let proteinRecipe = recipe("Chicken Bowl", slot: .lunch, p: 50, c: 5, f: 5)
        let carbRecipe = recipe("Pasta", slot: .lunch, p: 5, c: 60, f: 5)
        let intake = DayIntake(calories: 1200, protein: 30, carbs: 240, fat: 66)
        let recs = RecipeRecommender.recommend(
            recipes: [carbRecipe, proteinRecipe], targets: targets,
            intake: intake, now: at(hour: 12)
        )
        XCTAssertEqual(recs.first?.recipe.name, "Chicken Bowl")
        XCTAssertTrue(recs.first?.reason.contains("protein") ?? false)
    }

    func testPreferenceLiftsFrequentlyLoggedRecipe() {
        let plain = recipe("Salad A", slot: .any, p: 20, c: 20, f: 10)
        let favourite = recipe("Salad B", slot: .any, p: 20, c: 20, f: 10)
        favourite.timesLogged = 6
        favourite.lastLoggedAt = Date()
        let recs = RecipeRecommender.recommend(
            recipes: [plain, favourite], targets: targets,
            intake: .none, now: at(hour: 15)
        )
        XCTAssertEqual(recs.first?.recipe.name, "Salad B")
    }

    func testEmptyAndCaloriclessRecipesAreExcluded() {
        let empty = Recipe(name: "Empty", mealSlot: .lunch)
        let real = recipe("Real", slot: .lunch, p: 20, c: 20, f: 10)
        let recs = RecipeRecommender.recommend(
            recipes: [empty, real], targets: targets, intake: .none, now: at(hour: 12)
        )
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs.first?.recipe.name, "Real")
    }

    func testRespectsLimit() {
        let recipes = (0..<10).map { recipe("R\($0)", slot: .snack, p: 10, c: 10, f: 5) }
        let recs = RecipeRecommender.recommend(
            recipes: recipes, targets: targets, intake: .none, now: at(hour: 16), limit: 3
        )
        XCTAssertEqual(recs.count, 3)
    }
}

final class RecipeSeedTests: XCTestCase {
    func testSeedBuildsUsableRecipes() {
        let recipes = RecipeSeed.build()
        XCTAssertGreaterThanOrEqual(recipes.count, 20)
        for recipe in recipes {
            XCTAssertFalse(recipe.ingredients.isEmpty, "\(recipe.name) has no ingredients")
            XCTAssertGreaterThan(recipe.totalCalories, 0, "\(recipe.name) has no calories")
        }
    }

    func testSeedCoversEveryMealSlot() {
        let slots = Set(RecipeSeed.build().map(\.slot))
        XCTAssertTrue(slots.isSuperset(of: [.breakfast, .lunch, .dinner, .snack]))
    }
}
