import Foundation

protocol BarcodeLooking {
    func lookup(barcode: String) async throws -> BarcodeProduct?
}

struct BarcodeProduct {
    var name: String
    var brand: String?
    var servingSize: String?
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var micros: Micronutrients
}

/// Open Food Facts v2 product lookup by barcode (EAN-8, EAN-13, UPC-A).
/// Free API, no key, no new dependencies.
struct BarcodeService: BarcodeLooking {
    var session: URLSession = .shared

    func lookup(barcode: String) async throws -> BarcodeProduct? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode)?fields=product_name,brands,serving_size,nutriments") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NutritionLookupError.httpError(status: http.statusCode)
        }
        let decoded = try JSONDecoder().decode(OFFProductResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product else { return nil }
        return Self.map(product: product)
    }

    /// Maps an OFF v2 product to a BarcodeProduct, preferring per-serving
    /// values and falling back to per-100g when no serving data exists.
    static func map(product: OFFProduct) -> BarcodeProduct? {
        guard let n = product.nutriments else { return nil }
        let perServing = n.value("energy-kcal_serving") != nil
        let suffix = perServing ? "_serving" : "_100g"
        guard let kcal = n.value("energy-kcal" + suffix), kcal >= 0 else { return nil }

        var micros = Micronutrients()
        // OFF stores sodium in grams; the app tracks it in mg.
        if let sodium = n.value("sodium" + suffix) { micros.sodium = sodium * 1000 }
        if let sugars = n.value("sugars" + suffix) { micros.totalSugars = sugars }
        if let fiber = n.value("fiber" + suffix) { micros.fiber = fiber }
        if let satFat = n.value("saturated-fat" + suffix) { micros.saturatedFat = satFat }
        // OFF caffeine is in grams; the app tracks it in mg.
        if let caffeine = n.value("caffeine" + suffix) { micros.caffeine = caffeine * 1000 }

        let brand = product.brands?.trimmingCharacters(in: .whitespaces)
        return BarcodeProduct(
            name: product.product_name?.trimmingCharacters(in: .whitespaces) ?? "Unknown product",
            brand: brand?.isEmpty == false ? brand : nil,
            servingSize: perServing ? (product.serving_size ?? "1 serving") : "100 g",
            calories: kcal,
            protein: n.value("proteins" + suffix) ?? 0,
            carbs: n.value("carbohydrates" + suffix) ?? 0,
            fat: n.value("fat" + suffix) ?? 0,
            micros: micros
        )
    }

    // MARK: - Wire types

    struct OFFProductResponse: Decodable {
        let status: Int
        let product: OFFProduct?
    }

    struct OFFProduct: Decodable {
        let product_name: String?
        let brands: String?
        let serving_size: String?
        let nutriments: OFFNutriments?
    }

    /// OFF nutriment values arrive as numbers OR strings depending on the
    /// contributor — normalize both to Double.
    struct OFFNutriments: Decodable {
        private let raw: [String: Double]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            var values: [String: Double] = [:]
            for key in container.allKeys {
                if let d = try? container.decode(Double.self, forKey: key) {
                    values[key.stringValue] = d
                } else if let s = try? container.decode(String.self, forKey: key), let d = Double(s) {
                    values[key.stringValue] = d
                }
            }
            raw = values
        }

        func value(_ key: String) -> Double? { raw[key] }

        struct DynamicKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
    }
}
