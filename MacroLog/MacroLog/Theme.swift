import SwiftUI
import UIKit

/// App-wide light/dark preference. `system` follows the device.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// nil = follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// AppStorage keys for appearance + the customizable metric colors. Colors are
/// stored as "#RRGGBB" hex strings; an empty string means "use the default".
enum ThemeKeys {
    static let appearance = "theme_appearance"
    static let colorCalories = "theme_color_calories"
    static let colorProtein = "theme_color_protein"
    static let colorCarbs = "theme_color_carbs"
    static let colorFat = "theme_color_fat"
    static let colorWater = "theme_color_water"

    static func key(for metric: Metric) -> String {
        switch metric {
        case .calories: return colorCalories
        case .protein: return colorProtein
        case .carbs: return colorCarbs
        case .fat: return colorFat
        case .water: return colorWater
        }
    }
}

/// The five metric colors used by the Today rings/bar and the Trends chart.
/// Built from user overrides (falling back to the tuned defaults) and injected
/// through the environment so every tab updates when a color changes.
struct MetricPalette {
    var calories: Color
    var protein: Color
    var carbs: Color
    var fat: Color
    var water: Color

    func color(for metric: Metric) -> Color {
        switch metric {
        case .calories: return calories
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        case .water: return water
        }
    }

    /// The default (tuned, CVD-validated) palette — the source of truth is
    /// `Metric.color`, so defaults and the chart stay in sync.
    static let `default` = MetricPalette(
        calories: Metric.calories.color,
        protein: Metric.protein.color,
        carbs: Metric.carbs.color,
        fat: Metric.fat.color,
        water: Metric.water.color
    )

    /// Resolve a palette from stored hex overrides (empty = default).
    static func resolved(
        calories: String, protein: String, carbs: String, fat: String, water: String
    ) -> MetricPalette {
        MetricPalette(
            calories: Color(hex: calories) ?? Self.default.calories,
            protein: Color(hex: protein) ?? Self.default.protein,
            carbs: Color(hex: carbs) ?? Self.default.carbs,
            fat: Color(hex: fat) ?? Self.default.fat,
            water: Color(hex: water) ?? Self.default.water
        )
    }
}

private struct MetricPaletteKey: EnvironmentKey {
    static let defaultValue = MetricPalette.default
}

extension EnvironmentValues {
    var metricPalette: MetricPalette {
        get { self[MetricPaletteKey.self] }
        set { self[MetricPaletteKey.self] = newValue }
    }
}

// MARK: - Color <-> hex

extension Color {
    /// Parses "#RRGGBB" / "RRGGBB" (and the 8-digit RGBA form). Returns nil for
    /// empty or malformed strings so callers can fall back to a default.
    init?(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        let r, g, b, a: Double
        if cleaned.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        } else {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// "#RRGGBB" for persistence. Alpha is dropped (opaque metric colors).
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
