import SwiftUI
import UIKit

/// App-wide appearance. Light/Dark are fixed presets; Auto alternates with the
/// time of day (like iPhone's automatic setting); Custom uses the user's custom
/// background colour and derives light/dark from how dark that colour is.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, auto, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .auto: return "Auto"
        case .custom: return "Custom"
        }
    }

    /// Auto flips to dark in the evening/overnight.
    static func isNight(_ date: Date = .now) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour < 7 || hour >= 19
    }
}

/// AppStorage keys for appearance. The per-metric colour keys and the app
/// accent key were retired with the gold redesign — the ladder carries meaning
/// in the Trends chart, so those colours are no longer user-adjustable. Values
/// written by older builds are simply left on disk, unread.
enum ThemeKeys {
    static let appearance = "theme_appearance"
    static let background = "theme_background"
}

/// The five metric colors used by the Today rings/bar and the Trends chart.
/// Fixed to the gold ladder and injected through the environment; it stays a
/// struct rather than collapsing into `Metric.color` so a future theme (the
/// handoff sketches a parchment light mode) can supply a different one.
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

    /// The gold ladder — the source of truth is `Metric.color`, so the palette
    /// and the chart can't drift apart.
    static let `default` = MetricPalette(
        calories: Metric.calories.color,
        protein: Metric.protein.color,
        carbs: Metric.carbs.color,
        fat: Metric.fat.color,
        water: Metric.water.color
    )

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

/// The overall app accent (buttons, the capture controls, the orb). Gold, and
/// no longer customizable — see Settings → Appearance, where the accent and
/// per-metric colour pickers were retired so the gold ladder stays intact.
extension MetricPalette {
    static let defaultAppAccent = Lux.gold
}

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue = MetricPalette.defaultAppAccent
}

extension EnvironmentValues {
    var appAccent: Color {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }
}

/// A custom app background colour. nil = follow the system (light/dark)
/// background. When set, it overrides the background on every main screen.
private struct AppBackgroundKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var appBackground: Color? {
        get { self[AppBackgroundKey.self] }
        set { self[AppBackgroundKey.self] = newValue }
    }
}

extension View {
    /// Fills the screen behind scrollable content with a custom colour when one
    /// is set, hiding the default system scroll background. No-op when nil.
    @ViewBuilder
    func appBackground(_ color: Color?) -> some View {
        if let color {
            self
                .scrollContentBackground(.hidden)
                .background(color.ignoresSafeArea())
        } else {
            self
        }
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

    /// Whether this colour reads as dark (so overlaid text should be light).
    /// Uses Rec. 601 luma.
    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
    }
}
