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

/// The three chart/metric colours: mood, practice score, and activity minutes.
enum Metric: String, CaseIterable, Identifiable {
    case mood, score, minutes
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mood: return "Mood"
        case .score: return "Practice score"
        case .minutes: return "Activity minutes"
        }
    }

    /// Tuned defaults: warm amber for mood, calm teal for the score, soft
    /// violet for minutes — distinct under common colour-vision deficiencies.
    var color: Color {
        switch self {
        case .mood: return Color(.sRGB, red: 0.93, green: 0.69, blue: 0.25)
        case .score: return Color(.sRGB, red: 0.22, green: 0.64, blue: 0.60)
        case .minutes: return Color(.sRGB, red: 0.58, green: 0.48, blue: 0.83)
        }
    }
}

/// AppStorage keys for appearance + the customizable colours. Colours are
/// stored as "#RRGGBB" hex strings; an empty string means "use the default".
enum ThemeKeys {
    static let appearance = "theme_appearance"
    static let appAccent = "theme_app_accent"
    static let background = "theme_background"
    static let colorMood = "theme_color_mood"
    static let colorScore = "theme_color_score"
    static let colorMinutes = "theme_color_minutes"

    static func key(for metric: Metric) -> String {
        switch metric {
        case .mood: return colorMood
        case .score: return colorScore
        case .minutes: return colorMinutes
        }
    }
}

/// The metric colours used by the Today ring and the Trends charts. Built from
/// user overrides (falling back to the tuned defaults) and injected through
/// the environment so every tab updates when a colour changes.
struct MetricPalette {
    var mood: Color
    var score: Color
    var minutes: Color

    func color(for metric: Metric) -> Color {
        switch metric {
        case .mood: return mood
        case .score: return score
        case .minutes: return minutes
        }
    }

    static let `default` = MetricPalette(
        mood: Metric.mood.color,
        score: Metric.score.color,
        minutes: Metric.minutes.color
    )

    /// Resolve a palette from stored hex overrides (empty = default).
    static func resolved(mood: String, score: String, minutes: String) -> MetricPalette {
        MetricPalette(
            mood: Color(hex: mood) ?? Self.default.mood,
            score: Color(hex: score) ?? Self.default.score,
            minutes: Color(hex: minutes) ?? Self.default.minutes
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

/// The overall app accent (buttons, active tab, the mic, the "+"). The default
/// is MindLog's calm teal; customizable under Settings → Appearance.
extension MetricPalette {
    static let defaultAppAccent = Color(.sRGB, red: 0.24, green: 0.62, blue: 0.58)
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

    /// "#RRGGBB" for persistence. Alpha is dropped (opaque metric colours).
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
