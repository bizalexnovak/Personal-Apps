import Foundation
import SwiftData

/// Starter rows for the food database: the things USDA matches poorly —
/// branded alcohol (beer/wine/spirits/cocktails) and flagship fast-food items.
/// Values are the chains'/industry published per-serving numbers (close
/// approximations; users can edit any entry). Seeded once; more arrives via
/// scans, CSV imports, and community sync.
enum CustomFoodSeed {
    /// (name, brand, serving, kcal, protein, carbs, fat)
    private static let rows: [(String, String, String, Double, Double, Double, Double)] = [
        // MARK: Beer
        ("Bud Light", "Anheuser-Busch", "12 fl oz", 110, 0.9, 6.6, 0),
        ("Budweiser", "Anheuser-Busch", "12 fl oz", 145, 1.3, 10.6, 0),
        ("Michelob Ultra", "Anheuser-Busch", "12 fl oz", 95, 0.6, 2.6, 0),
        ("Coors Light", "Coors", "12 fl oz", 102, 0.8, 5, 0),
        ("Miller Lite", "Miller", "12 fl oz", 96, 0.9, 3.2, 0),
        ("Corona Extra", "Corona", "12 fl oz", 148, 1.2, 13.9, 0),
        ("Corona Light", "Corona", "12 fl oz", 99, 0.8, 5, 0),
        ("Modelo Especial", "Modelo", "12 fl oz", 144, 1.2, 13.6, 0),
        ("Heineken", "Heineken", "12 fl oz", 142, 1.1, 11.4, 0),
        ("Stella Artois", "Stella Artois", "12 fl oz", 142, 1.2, 11.7, 0),
        ("Blue Moon Belgian White", "Blue Moon", "12 fl oz", 168, 1.9, 14.1, 0),
        ("Guinness Draught", "Guinness", "12 fl oz", 125, 1.3, 9.8, 0),
        ("IPA (typical craft)", "", "12 fl oz", 200, 2, 15, 0),
        ("Light beer (generic)", "", "12 fl oz", 103, 0.9, 5.8, 0),
        ("Regular beer (generic)", "", "12 fl oz", 153, 1.6, 12.6, 0),
        ("Angry Orchard Crisp Apple", "Angry Orchard", "12 fl oz", 210, 0, 25, 0),
        // MARK: Seltzers & canned
        ("White Claw Hard Seltzer", "White Claw", "12 fl oz", 100, 0, 2, 0),
        ("Truly Hard Seltzer", "Truly", "12 fl oz", 100, 0, 2, 0),
        ("High Noon", "High Noon", "12 fl oz", 100, 0, 2.6, 0),
        // MARK: Wine
        ("Red wine", "", "5 fl oz", 125, 0.1, 3.8, 0),
        ("White wine", "", "5 fl oz", 121, 0.1, 3.8, 0),
        ("Rosé wine", "", "5 fl oz", 125, 0.1, 3.8, 0),
        ("Champagne / sparkling wine", "", "4 fl oz", 84, 0.1, 1.6, 0),
        ("Sangria", "", "6 fl oz", 150, 0.3, 12, 0),
        // MARK: Spirits & cocktails
        ("Vodka", "", "1.5 fl oz (80 proof)", 97, 0, 0, 0),
        ("Whiskey", "", "1.5 fl oz (80 proof)", 97, 0, 0, 0),
        ("Tequila", "", "1.5 fl oz (80 proof)", 97, 0, 0, 0),
        ("Rum", "", "1.5 fl oz (80 proof)", 97, 0, 0, 0),
        ("Gin", "", "1.5 fl oz (80 proof)", 97, 0, 0, 0),
        ("Margarita", "", "1 cocktail", 270, 0, 18, 0),
        ("Old Fashioned", "", "1 cocktail", 155, 0, 4, 0),
        ("Mojito", "", "1 cocktail", 165, 0, 17, 0),
        ("Gin & Tonic", "", "1 cocktail", 140, 0, 12, 0),
        ("Rum & Coke", "", "1 cocktail", 185, 0, 20, 0),
        ("Moscow Mule", "", "1 cocktail", 180, 0, 20, 0),
        ("Aperol Spritz", "", "1 cocktail", 125, 0, 11, 0),
        ("Espresso Martini", "", "1 cocktail", 270, 0, 24, 0),
        ("Mimosa", "", "1 cocktail", 75, 0, 6, 0),
        ("Bloody Mary", "", "1 cocktail", 120, 1, 9, 0),
        ("Baileys Irish Cream", "Baileys", "1.5 fl oz", 147, 1, 11, 6),
        // MARK: Fast food — burgers & chicken
        ("Big Mac", "McDonald's", "1 burger", 550, 25, 45, 30),
        ("Quarter Pounder with Cheese", "McDonald's", "1 burger", 520, 30, 42, 26),
        ("McDouble", "McDonald's", "1 burger", 400, 22, 33, 20),
        ("Chicken McNuggets", "McDonald's", "10 pieces", 410, 23, 26, 24),
        ("French fries (medium)", "McDonald's", "1 medium", 320, 5, 43, 15),
        ("Egg McMuffin", "McDonald's", "1 sandwich", 310, 17, 30, 13),
        ("Whopper", "Burger King", "1 burger", 670, 28, 54, 40),
        ("Dave's Single", "Wendy's", "1 burger", 590, 30, 39, 34),
        ("Baconator", "Wendy's", "1 burger", 960, 58, 39, 65),
        ("Double-Double", "In-N-Out", "1 burger", 670, 37, 39, 41),
        ("Chicken Sandwich", "Chick-fil-A", "1 sandwich", 420, 28, 41, 18),
        ("Chicken Nuggets", "Chick-fil-A", "12 pieces", 380, 40, 16, 18),
        ("Chicken Sandwich", "Popeyes", "1 sandwich", 700, 28, 50, 42),
        ("Original Recipe Chicken Breast", "KFC", "1 breast", 390, 39, 11, 21),
        // MARK: Fast food — Mexican, pizza, subs
        ("Crunchy Taco", "Taco Bell", "1 taco", 170, 8, 13, 9),
        ("Crunchwrap Supreme", "Taco Bell", "1 item", 530, 16, 71, 21),
        ("Chicken Burrito Bowl (rice, beans, salsa, cheese)", "Chipotle", "1 bowl", 625, 45, 60, 22),
        ("Pepperoni pizza slice (14\" hand-tossed)", "Domino's", "1 slice", 300, 12, 34, 12),
        ("Turkey Breast 6\" sub", "Subway", "1 sandwich", 270, 18, 40, 4),
        // MARK: Coffee & breakfast chains
        ("Caffè Latte, grande, 2% milk", "Starbucks", "16 fl oz", 190, 13, 19, 7),
        ("Glazed Donut", "Dunkin'", "1 donut", 240, 4, 33, 11),
    ]

    private static let seededFlag = "custom_foods_seeded_v1"

    /// Insert once (deduped through the same key as every other source, so a
    /// community or scanned copy of an item never duplicates it).
    @MainActor
    static func seedIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seededFlag) else { return }
        defaults.set(true, forKey: seededFlag)
        for (name, brand, serving, kcal, p, c, f) in rows {
            CustomFoodStore.addIfNew(CustomFood(
                name: name, brand: brand, serving: serving,
                calories: kcal, protein: p, carbs: c, fat: f,
                source: "seed", synced: true
            ), in: context)
        }
        try? context.save()
    }

    static var count: Int { rows.count }
}
