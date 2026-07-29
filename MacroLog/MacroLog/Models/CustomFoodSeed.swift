import Foundation
import SwiftData

/// Starter rows for the food database: the things USDA matches poorly —
/// branded alcohol, sodas and energy drinks (with caffeine), and the flagship
/// menu items of the big chains. Values are the chains'/industry published
/// per-serving numbers (close approximations; users can edit any entry).
/// Seeded once; more arrives via scans, CSV imports, and community sync.
enum CustomFoodSeed {
    struct Row {
        let name: String
        let brand: String
        let serving: String
        let kcal: Double
        let p: Double
        let c: Double
        let f: Double
        /// mg caffeine, recorded as a micronutrient when non-zero.
        var caffeine: Double = 0

        init(_ name: String, _ brand: String, _ serving: String,
             _ kcal: Double, _ p: Double, _ c: Double, _ f: Double,
             caffeine: Double = 0) {
            self.name = name; self.brand = brand; self.serving = serving
            self.kcal = kcal; self.p = p; self.c = c; self.f = f
            self.caffeine = caffeine
        }
    }

    static let rows: [Row] = [
        // MARK: Beer
        .init("Bud Light", "Anheuser-Busch", "12 fl oz", 110, 0.9, 6.6, 0),
        .init("Budweiser", "Anheuser-Busch", "12 fl oz", 145, 1.3, 10.6, 0),
        .init("Michelob Ultra", "Anheuser-Busch", "12 fl oz", 95, 0.6, 2.6, 0),
        .init("Busch Light", "Anheuser-Busch", "12 fl oz", 95, 0.7, 3.2, 0),
        .init("Natural Light", "Anheuser-Busch", "12 fl oz", 95, 0.7, 3.2, 0),
        .init("Coors Light", "Coors", "12 fl oz", 102, 0.8, 5, 0),
        .init("Miller Lite", "Miller", "12 fl oz", 96, 0.9, 3.2, 0),
        .init("Corona Extra", "Corona", "12 fl oz", 148, 1.2, 13.9, 0),
        .init("Corona Light", "Corona", "12 fl oz", 99, 0.8, 5, 0),
        .init("Modelo Especial", "Modelo", "12 fl oz", 144, 1.2, 13.6, 0),
        .init("Pacifico", "Pacifico", "12 fl oz", 146, 1.1, 13, 0),
        .init("Heineken", "Heineken", "12 fl oz", 142, 1.1, 11.4, 0),
        .init("Stella Artois", "Stella Artois", "12 fl oz", 142, 1.2, 11.7, 0),
        .init("Blue Moon Belgian White", "Blue Moon", "12 fl oz", 168, 1.9, 14.1, 0),
        .init("Guinness Draught", "Guinness", "12 fl oz", 125, 1.3, 9.8, 0),
        .init("Sierra Nevada Pale Ale", "Sierra Nevada", "12 fl oz", 175, 1.8, 14.5, 0),
        .init("IPA (typical craft)", "", "12 fl oz", 200, 2, 15, 0),
        .init("Light beer (generic)", "", "12 fl oz", 103, 0.9, 5.8, 0),
        .init("Regular beer (generic)", "", "12 fl oz", 153, 1.6, 12.6, 0),
        .init("Angry Orchard Crisp Apple", "Angry Orchard", "12 fl oz", 210, 0, 25, 0),
        // MARK: Seltzers
        .init("White Claw Hard Seltzer", "White Claw", "12 fl oz", 100, 0, 2, 0),
        .init("Truly Hard Seltzer", "Truly", "12 fl oz", 100, 0, 2, 0),
        .init("High Noon", "High Noon", "12 fl oz", 100, 0, 2.6, 0),
        // MARK: Wine
        .init("Red wine", "", "5 fl oz", 125, 0.1, 3.8, 0),
        .init("White wine", "", "5 fl oz", 121, 0.1, 3.8, 0),
        .init("Rosé wine", "", "5 fl oz", 125, 0.1, 3.8, 0),
        .init("Champagne / sparkling wine", "", "4 fl oz", 84, 0.1, 1.6, 0),
        .init("Sangria", "", "6 fl oz", 150, 0.3, 12, 0),
        // MARK: Spirits & cocktails
        .init("Vodka", "", "1.5 fl oz (80 proof)", 97, 0, 0, 0),
        .init("Whiskey", "", "1.5 fl oz (80 proof)", 97, 0, 0, 0),
        .init("Tequila", "", "1.5 fl oz (80 proof)", 97, 0, 0, 0),
        .init("Rum", "", "1.5 fl oz (80 proof)", 97, 0, 0, 0),
        .init("Gin", "", "1.5 fl oz (80 proof)", 97, 0, 0, 0),
        .init("Margarita", "", "1 cocktail", 270, 0, 18, 0),
        .init("Old Fashioned", "", "1 cocktail", 155, 0, 4, 0),
        .init("Mojito", "", "1 cocktail", 165, 0, 17, 0),
        .init("Gin & Tonic", "", "1 cocktail", 140, 0, 12, 0),
        .init("Rum & Coke", "", "1 cocktail", 185, 0, 20, 0),
        .init("Moscow Mule", "", "1 cocktail", 180, 0, 20, 0),
        .init("Aperol Spritz", "", "1 cocktail", 125, 0, 11, 0),
        .init("Espresso Martini", "", "1 cocktail", 270, 0, 24, 0, caffeine: 65),
        .init("Mimosa", "", "1 cocktail", 75, 0, 6, 0),
        .init("Bloody Mary", "", "1 cocktail", 120, 1, 9, 0),
        .init("Baileys Irish Cream", "Baileys", "1.5 fl oz", 147, 1, 11, 6),
        // MARK: Sodas & energy drinks (caffeine recorded)
        .init("Coca-Cola", "Coca-Cola", "12 fl oz", 140, 0, 39, 0, caffeine: 34),
        .init("Diet Coke", "Coca-Cola", "12 fl oz", 0, 0, 0, 0, caffeine: 46),
        .init("Coke Zero", "Coca-Cola", "12 fl oz", 0, 0, 0, 0, caffeine: 34),
        .init("Pepsi", "Pepsi", "12 fl oz", 150, 0, 41, 0, caffeine: 38),
        .init("Dr Pepper", "Dr Pepper", "12 fl oz", 150, 0, 40, 0, caffeine: 41),
        .init("Mountain Dew", "Mountain Dew", "12 fl oz", 170, 0, 46, 0, caffeine: 54),
        .init("Sprite", "Coca-Cola", "12 fl oz", 140, 0, 38, 0),
        .init("Red Bull", "Red Bull", "8.4 fl oz", 110, 1, 28, 0, caffeine: 80),
        .init("Red Bull Sugarfree", "Red Bull", "8.4 fl oz", 10, 1, 2, 0, caffeine: 80),
        .init("Monster Energy", "Monster", "16 fl oz", 210, 0, 54, 0, caffeine: 160),
        .init("Monster Zero Ultra", "Monster", "16 fl oz", 10, 0, 4, 0, caffeine: 140),
        .init("Celsius", "Celsius", "12 fl oz", 10, 0, 2, 0, caffeine: 200),
        .init("Bang Energy", "Bang", "16 fl oz", 0, 0, 0, 0, caffeine: 300),
        .init("5-hour Energy", "5-hour Energy", "1 shot (1.93 fl oz)", 4, 0, 0, 0, caffeine: 200),
        .init("Gatorade", "Gatorade", "20 fl oz", 140, 0, 36, 0),
        .init("Powerade", "Powerade", "20 fl oz", 130, 0, 35, 0),
        // MARK: McDonald's
        .init("Big Mac", "McDonald's", "1 burger", 550, 25, 45, 30),
        .init("Quarter Pounder with Cheese", "McDonald's", "1 burger", 520, 30, 42, 26),
        .init("Double Quarter Pounder with Cheese", "McDonald's", "1 burger", 740, 48, 43, 42),
        .init("McDouble", "McDonald's", "1 burger", 400, 22, 33, 20),
        .init("Cheeseburger", "McDonald's", "1 burger", 300, 15, 32, 13),
        .init("Hamburger", "McDonald's", "1 burger", 250, 12, 31, 9),
        .init("McChicken", "McDonald's", "1 sandwich", 400, 14, 39, 21),
        .init("McCrispy", "McDonald's", "1 sandwich", 470, 26, 46, 20),
        .init("Spicy McCrispy", "McDonald's", "1 sandwich", 530, 27, 48, 26),
        .init("Filet-O-Fish", "McDonald's", "1 sandwich", 390, 16, 39, 19),
        // Per piece, so "6 McNuggets" / "10 McNuggets" scale naturally.
        .init("Chicken McNuggets", "McDonald's", "1 nugget", 41, 2.3, 2.6, 2.4),
        .init("French fries (small)", "McDonald's", "1 small", 230, 3, 31, 11),
        .init("French fries (medium)", "McDonald's", "1 medium", 320, 5, 43, 15),
        .init("French fries (large)", "McDonald's", "1 large", 480, 7, 65, 23),
        .init("Egg McMuffin", "McDonald's", "1 sandwich", 310, 17, 30, 13),
        .init("Sausage McMuffin with Egg", "McDonald's", "1 sandwich", 480, 21, 30, 31),
        .init("Bacon Egg & Cheese Biscuit", "McDonald's", "1 sandwich", 460, 19, 38, 26),
        .init("Sausage Burrito", "McDonald's", "1 burrito", 300, 12, 25, 16),
        .init("Hash Browns", "McDonald's", "1 order", 140, 2, 18, 8),
        .init("Hotcakes", "McDonald's", "3 pancakes with syrup & butter", 580, 9, 102, 15),
        .init("Oreo McFlurry", "McDonald's", "1 regular", 510, 12, 80, 16),
        .init("Vanilla Cone", "McDonald's", "1 cone", 200, 5, 33, 5),
        // MARK: Chick-fil-A
        .init("Chicken Sandwich", "Chick-fil-A", "1 sandwich", 420, 28, 41, 18),
        .init("Deluxe Chicken Sandwich", "Chick-fil-A", "1 sandwich", 500, 32, 43, 23),
        .init("Spicy Chicken Sandwich", "Chick-fil-A", "1 sandwich", 450, 28, 45, 19),
        .init("Grilled Chicken Sandwich", "Chick-fil-A", "1 sandwich", 390, 28, 44, 12),
        .init("Chicken Nuggets", "Chick-fil-A", "1 nugget", 31, 3.4, 1.4, 1.4),
        .init("Grilled Nuggets", "Chick-fil-A", "1 nugget", 16, 3.1, 0.1, 0.4),
        .init("Waffle Potato Fries", "Chick-fil-A", "1 medium", 420, 5, 45, 24),
        .init("Mac & Cheese", "Chick-fil-A", "1 medium", 450, 17, 29, 29),
        .init("Chick-fil-A Lemonade", "Chick-fil-A", "1 medium", 220, 0, 58, 0),
        .init("Cookies & Cream Milkshake", "Chick-fil-A", "1 regular", 630, 13, 91, 25),
        // MARK: Taco Bell
        .init("Crunchy Taco", "Taco Bell", "1 taco", 170, 8, 13, 9),
        .init("Soft Taco", "Taco Bell", "1 taco", 180, 9, 18, 9),
        .init("Doritos Locos Taco", "Taco Bell", "1 taco", 170, 8, 13, 9),
        .init("Crunchwrap Supreme", "Taco Bell", "1 item", 530, 16, 71, 21),
        .init("Beefy 5-Layer Burrito", "Taco Bell", "1 burrito", 490, 18, 63, 18),
        .init("Bean Burrito", "Taco Bell", "1 burrito", 350, 13, 54, 9),
        .init("Chicken Quesadilla", "Taco Bell", "1 quesadilla", 510, 27, 41, 27),
        .init("Mexican Pizza", "Taco Bell", "1 item", 550, 20, 47, 31),
        .init("Cheesy Gordita Crunch", "Taco Bell", "1 item", 500, 20, 41, 28),
        .init("Chalupa Supreme (beef)", "Taco Bell", "1 chalupa", 350, 13, 33, 18),
        .init("Nachos BellGrande", "Taco Bell", "1 order", 740, 16, 82, 38),
        // MARK: Chipotle (build-a-bowl components)
        .init("Chicken", "Chipotle", "1 serving (4 oz)", 180, 32, 0, 7),
        .init("Steak", "Chipotle", "1 serving (4 oz)", 150, 21, 1, 6),
        .init("Carnitas", "Chipotle", "1 serving (4 oz)", 210, 23, 0, 12),
        .init("Barbacoa", "Chipotle", "1 serving (4 oz)", 170, 24, 2, 7),
        .init("Sofritas", "Chipotle", "1 serving (4 oz)", 150, 8, 9, 10),
        .init("White Rice", "Chipotle", "1 serving (4 oz)", 210, 4, 40, 4),
        .init("Brown Rice", "Chipotle", "1 serving (4 oz)", 210, 4, 36, 6),
        .init("Black Beans", "Chipotle", "1 serving (4 oz)", 130, 8, 22, 2),
        .init("Pinto Beans", "Chipotle", "1 serving (4 oz)", 130, 8, 21, 2),
        .init("Fajita Veggies", "Chipotle", "1 serving", 20, 1, 5, 0),
        .init("Fresh Tomato Salsa", "Chipotle", "1 serving", 25, 0, 4, 0),
        .init("Roasted Chili-Corn Salsa", "Chipotle", "1 serving", 80, 3, 16, 2),
        .init("Cheese", "Chipotle", "1 serving", 110, 6, 1, 8),
        .init("Sour Cream", "Chipotle", "1 serving", 110, 2, 2, 9),
        .init("Guacamole", "Chipotle", "1 serving", 230, 2, 8, 22),
        .init("Queso Blanco", "Chipotle", "1 serving", 120, 5, 4, 9),
        .init("Flour Tortilla", "Chipotle", "1 tortilla", 320, 9, 50, 9),
        .init("Chips", "Chipotle", "1 regular bag", 540, 7, 73, 25),
        // MARK: Wendy's
        .init("Dave's Single", "Wendy's", "1 burger", 590, 30, 39, 34),
        .init("Dave's Double", "Wendy's", "1 burger", 810, 48, 40, 51),
        .init("Jr. Bacon Cheeseburger", "Wendy's", "1 burger", 380, 20, 26, 23),
        .init("Baconator", "Wendy's", "1 burger", 960, 58, 39, 65),
        .init("Spicy Chicken Sandwich", "Wendy's", "1 sandwich", 490, 28, 49, 20),
        .init("Chicken Nuggets", "Wendy's", "1 nugget", 45, 2.4, 2.7, 2.8),
        .init("French fries (medium)", "Wendy's", "1 medium", 420, 6, 56, 19),
        .init("Chili", "Wendy's", "1 small", 240, 15, 16, 11),
        .init("Chocolate Frosty", "Wendy's", "1 medium", 580, 15, 98, 15),
        .init("Baked Potato (plain)", "Wendy's", "1 potato", 270, 7, 61, 0),
        // MARK: Burger King
        .init("Whopper", "Burger King", "1 burger", 670, 28, 54, 40),
        .init("Whopper with Cheese", "Burger King", "1 burger", 760, 32, 56, 46),
        .init("Bacon King", "Burger King", "1 burger", 1150, 61, 49, 79),
        .init("Original Chicken Sandwich", "Burger King", "1 sandwich", 660, 23, 48, 40),
        .init("French fries (medium)", "Burger King", "1 medium", 380, 4, 53, 17),
        // MARK: In-N-Out / Five Guys / Shake Shack
        .init("Double-Double", "In-N-Out", "1 burger", 670, 37, 39, 41),
        .init("Cheeseburger", "In-N-Out", "1 burger", 480, 22, 39, 27),
        .init("Hamburger", "In-N-Out", "1 burger", 390, 16, 39, 19),
        .init("French fries", "In-N-Out", "1 order", 400, 7, 54, 18),
        .init("Cheeseburger", "Five Guys", "1 burger (2 patties)", 980, 47, 40, 71),
        .init("Hamburger", "Five Guys", "1 burger (2 patties)", 700, 39, 39, 43),
        .init("Little Cheeseburger", "Five Guys", "1 burger", 610, 29, 40, 37),
        .init("French fries", "Five Guys", "1 regular", 950, 15, 131, 41),
        .init("ShackBurger (single)", "Shake Shack", "1 burger", 500, 26, 27, 30),
        .init("Crinkle Cut Fries", "Shake Shack", "1 order", 470, 7, 63, 22),
        // MARK: Subway (6-inch on white, standard veggies)
        .init("Turkey Breast 6\" sub", "Subway", "1 sandwich", 270, 18, 40, 4),
        .init("Italian BMT 6\" sub", "Subway", "1 sandwich", 390, 19, 40, 17),
        .init("Tuna 6\" sub", "Subway", "1 sandwich", 450, 19, 39, 24),
        .init("Meatball Marinara 6\" sub", "Subway", "1 sandwich", 430, 19, 46, 18),
        .init("Steak & Cheese 6\" sub", "Subway", "1 sandwich", 340, 23, 36, 11),
        .init("Sweet Onion Chicken Teriyaki 6\" sub", "Subway", "1 sandwich", 320, 23, 47, 5),
        .init("Spicy Italian 6\" sub", "Subway", "1 sandwich", 450, 18, 40, 24),
        .init("Veggie Delite 6\" sub", "Subway", "1 sandwich", 200, 8, 36, 2),
        // MARK: KFC / Popeyes
        .init("Original Recipe Chicken Breast", "KFC", "1 breast", 390, 39, 11, 21),
        .init("Original Recipe Drumstick", "KFC", "1 drumstick", 130, 12, 4, 7),
        .init("Mashed Potatoes with Gravy", "KFC", "1 individual", 130, 2, 19, 4),
        .init("Biscuit", "KFC", "1 biscuit", 180, 4, 23, 8),
        .init("Chicken Sandwich", "Popeyes", "1 sandwich", 700, 28, 50, 42),
        .init("Spicy Chicken Sandwich", "Popeyes", "1 sandwich", 700, 28, 50, 42),
        .init("Buttermilk Biscuit", "Popeyes", "1 biscuit", 210, 4, 26, 10),
        .init("Red Beans & Rice", "Popeyes", "1 regular", 230, 8, 31, 9),
        // MARK: Pizza
        .init("Pepperoni pizza slice (14\" hand-tossed)", "Domino's", "1 slice", 300, 12, 34, 12),
        .init("Cheese pizza slice (14\" hand-tossed)", "Domino's", "1 slice", 280, 11, 34, 10),
        .init("Pepperoni pizza slice (large)", "Pizza Hut", "1 slice", 330, 14, 35, 15),
        .init("Cheese pizza slice (large)", "Papa John's", "1 slice", 300, 12, 37, 11),
        // MARK: Starbucks (grande, 2% milk unless noted)
        .init("Caffè Latte", "Starbucks", "16 fl oz (grande)", 190, 13, 19, 7, caffeine: 150),
        .init("Cappuccino", "Starbucks", "16 fl oz (grande)", 140, 9, 14, 5, caffeine: 150),
        .init("Caffè Americano", "Starbucks", "16 fl oz (grande)", 15, 1, 2, 0, caffeine: 225),
        .init("Brewed Coffee (Pike Place)", "Starbucks", "16 fl oz (grande)", 5, 0, 0, 0, caffeine: 310),
        .init("Cold Brew", "Starbucks", "16 fl oz (grande)", 5, 0, 0, 0, caffeine: 205),
        .init("Caramel Macchiato", "Starbucks", "16 fl oz (grande)", 250, 10, 35, 7, caffeine: 150),
        .init("Caffè Mocha", "Starbucks", "16 fl oz (grande)", 370, 13, 44, 15, caffeine: 175),
        .init("White Chocolate Mocha", "Starbucks", "16 fl oz (grande)", 430, 14, 54, 18, caffeine: 150),
        .init("Chai Tea Latte", "Starbucks", "16 fl oz (grande)", 240, 6, 45, 4, caffeine: 95),
        .init("Matcha Latte", "Starbucks", "16 fl oz (grande)", 240, 12, 34, 7, caffeine: 80),
        .init("Pumpkin Spice Latte", "Starbucks", "16 fl oz (grande)", 390, 14, 52, 14, caffeine: 150),
        .init("Vanilla Sweet Cream Cold Brew", "Starbucks", "16 fl oz (grande)", 110, 1, 14, 6, caffeine: 185),
        .init("Iced Brown Sugar Oatmilk Shaken Espresso", "Starbucks", "16 fl oz (grande)", 120, 2, 18, 4, caffeine: 255),
        .init("Java Chip Frappuccino", "Starbucks", "16 fl oz (grande)", 440, 6, 66, 18, caffeine: 105),
        .init("Pink Drink", "Starbucks", "16 fl oz (grande)", 140, 1, 27, 2, caffeine: 45),
        .init("Bacon Gouda & Egg Sandwich", "Starbucks", "1 sandwich", 360, 17, 34, 18),
        .init("Butter Croissant", "Starbucks", "1 croissant", 260, 5, 27, 15),
        .init("Banana Bread", "Starbucks", "1 slice", 420, 6, 52, 22),
        // MARK: Dunkin'
        .init("Glazed Donut", "Dunkin'", "1 donut", 240, 4, 33, 11),
        .init("Boston Kreme Donut", "Dunkin'", "1 donut", 300, 4, 39, 14),
        .init("Plain Bagel", "Dunkin'", "1 bagel", 310, 11, 63, 3),
        .init("Everything Bagel", "Dunkin'", "1 bagel", 340, 12, 64, 5),
        .init("Sausage Egg & Cheese Croissant", "Dunkin'", "1 sandwich", 720, 22, 40, 52),
        .init("Original Blend Coffee (black)", "Dunkin'", "14 fl oz (medium)", 5, 0, 0, 0, caffeine: 210),
        .init("Latte", "Dunkin'", "14 fl oz (medium)", 170, 8, 16, 8, caffeine: 166),
        // MARK: Panera
        .init("Broccoli Cheddar Soup", "Panera", "1 cup", 360, 14, 24, 24),
        .init("Mac & Cheese", "Panera", "1 cup", 480, 17, 34, 30),
    ]

    private static let seededFlag = "custom_foods_seeded_v2"
    private static let legacyFlag = "custom_foods_seeded_v1"

    /// Insert once (deduped through the same key as every other source, so a
    /// community or scanned copy of an item never duplicates it). The v2 flag
    /// lets this expanded set top up installs seeded with the original v1 set
    /// — addIfNew skips everything they already have.
    @MainActor
    static func seedIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seededFlag) else { return }
        defaults.set(true, forKey: seededFlag)
        defaults.set(true, forKey: legacyFlag)
        for row in rows {
            var micros = Micronutrients()
            if row.caffeine > 0 { micros.caffeine = row.caffeine }
            CustomFoodStore.addIfNew(CustomFood(
                name: row.name, brand: row.brand, serving: row.serving,
                calories: row.kcal, protein: row.p, carbs: row.c, fat: row.f,
                microsData: micros.isEmpty ? nil : try? JSONEncoder().encode(micros),
                source: "seed", synced: true
            ), in: context)
        }
        try? context.save()
    }

    static var count: Int { rows.count }
}
