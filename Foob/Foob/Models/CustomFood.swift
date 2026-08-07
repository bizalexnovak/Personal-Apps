import Foundation
import SwiftData

/// One food in the app's own nutrition database — the store that gets searched
/// BEFORE the USDA API. Rows accumulate from four sources:
///  - "scan":      every nutrition/supplement label the user scans is added
///                 automatically (no duplicates — see `nameKey`)
///  - "import":    CSV sheets uploaded in Settings → Food database
///                 (restaurant menus, beer/wine lists, …)
///  - "community": rows contributed by other users of the same proxy server,
///                 pulled down by `CommunitySync`
///  - "seed":      the bundled starter set (common alcohol + fast food)
///
/// Values are PER SERVING (the serving text says what a serving is), matching
/// how nutrition labels are printed.
@Model
final class CustomFood {
    // CloudKit rules — see the note on `Meal`.
    var id: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    /// Serving as printed/entered, e.g. "1 can (12 fl oz)". Display-only.
    var serving: String = "1 serving"
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    /// Micronutrients JSON, same encoding as `FoodItem.microsData`.
    var microsData: Data?
    /// One of "scan" / "import" / "community" / "seed".
    var source: String = "import"
    /// Normalized name+brand — the dedup key. Two scans of the same product, or
    /// a scan matching a community row, collapse to one entry. CloudKit can't
    /// enforce uniqueness, so `CustomFoodStore.addIfNew` fetches on this key
    /// before inserting, and `dedupe(in:)` collapses rows that arrive from sync.
    var nameKey: String = ""
    var createdAt: Date = Date.distantPast
    /// False until this row has been pushed to the community database.
    /// Community/seed rows are created true (nothing to push).
    var synced: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        serving: String = "1 serving",
        calories: Double,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        microsData: Data? = nil,
        source: String,
        createdAt: Date = .now,
        synced: Bool = false
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.serving = serving
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.microsData = microsData
        self.source = source
        self.nameKey = CustomFoodStore.nameKey(name: name, brand: brand)
        self.createdAt = createdAt
        self.synced = synced
    }

    /// Combined display name ("Corona Extra" / "Big Mac — McDonald's").
    var displayName: String {
        brand.isEmpty || name.localizedCaseInsensitiveContains(brand)
            ? name
            : "\(name) — \(brand)"
    }
}
