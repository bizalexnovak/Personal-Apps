import Foundation

/// One kind of wellbeing activity the app can log. Points-per-minute and the
/// daily cap encode the evidence loosely: short, potent practices (gratitude,
/// breathwork) earn fast but cap early; long, gentle ones (a screen break)
/// earn slowly but can run longer. Caps are what make variety beat grinding —
/// three hours of one thing can't max the day on its own.
struct WellbeingActivity: Identifiable, Equatable {
    let id: String
    let name: String
    /// SF Symbol shown on chips, grids, and log rows.
    let icon: String
    let pointsPerMinute: Double
    /// Only the first `capMinutes` per day earn points.
    let capMinutes: Double
    /// Duration chips offered when logging (minutes).
    let presetMinutes: [Double]
    /// One-line "why this helps" shown when logging — informational, not
    /// medical advice.
    let why: String

    var maxDailyPoints: Double { pointsPerMinute * capMinutes }
}

/// The built-in activity set. A fixed catalog (not user data) so the score
/// stays comparable across days and devices; custom activities are a roadmap
/// item and will need a stored catalog.
enum ActivityCatalog {
    static let meditation = "meditation"
    static let breathwork = "breathwork"
    static let exercise = "exercise"
    static let outdoors = "outdoors"
    static let social = "social"
    static let gratitude = "gratitude"
    static let reading = "reading"
    static let screenBreak = "screen_break"
    static let therapy = "therapy"
    static let creative = "creative"

    static let all: [WellbeingActivity] = [
        WellbeingActivity(
            id: meditation, name: "Meditation", icon: "figure.mind.and.body",
            pointsPerMinute: 1.2, capMinutes: 30, presetMinutes: [5, 10, 15, 20, 30],
            why: "Regular meditation is one of the best-studied ways to lower stress and sharpen attention."
        ),
        WellbeingActivity(
            id: breathwork, name: "Breathing", icon: "wind",
            pointsPerMinute: 1.5, capMinutes: 10, presetMinutes: [1, 2, 3, 5, 10],
            why: "Slow, deliberate breathing calms the nervous system in minutes."
        ),
        WellbeingActivity(
            id: exercise, name: "Exercise", icon: "figure.run",
            pointsPerMinute: 0.8, capMinutes: 45, presetMinutes: [15, 30, 45, 60, 90],
            why: "Movement is as effective as many first-line treatments for low mood."
        ),
        WellbeingActivity(
            id: outdoors, name: "Time outside", icon: "leaf",
            pointsPerMinute: 0.7, capMinutes: 60, presetMinutes: [10, 20, 30, 45, 60],
            why: "Daylight and green space reliably lift mood and settle rumination."
        ),
        WellbeingActivity(
            id: social, name: "Social time", icon: "person.2",
            pointsPerMinute: 0.5, capMinutes: 90, presetMinutes: [15, 30, 60, 90, 120],
            why: "Real connection — a call counts — is the strongest long-run predictor of wellbeing."
        ),
        WellbeingActivity(
            id: gratitude, name: "Gratitude", icon: "heart.text.square",
            pointsPerMinute: 2.0, capMinutes: 10, presetMinutes: [2, 5, 10],
            why: "Naming a few good things rewires what your attention reaches for first."
        ),
        WellbeingActivity(
            id: reading, name: "Reading", icon: "book",
            pointsPerMinute: 0.5, capMinutes: 45, presetMinutes: [10, 20, 30, 45, 60],
            why: "Deep reading is a low-stimulation reset for an overstimulated brain."
        ),
        WellbeingActivity(
            id: screenBreak, name: "Screen break", icon: "iphone.slash",
            pointsPerMinute: 0.25, capMinutes: 120, presetMinutes: [30, 60, 90, 120],
            why: "Stretches away from feeds and pings give your attention room to recover."
        ),
        WellbeingActivity(
            id: therapy, name: "Therapy", icon: "bubble.left.and.bubble.right",
            pointsPerMinute: 1.0, capMinutes: 60, presetMinutes: [30, 45, 60],
            why: "Talking it through with a professional is care, not crisis management."
        ),
        WellbeingActivity(
            id: creative, name: "Creative time", icon: "paintpalette",
            pointsPerMinute: 0.6, capMinutes: 60, presetMinutes: [15, 30, 45, 60],
            why: "Making something — music, sketches, cooking for fun — is active rest."
        ),
    ]

    private static let byID: [String: WellbeingActivity] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Never fails: unknown ids (from an older/newer catalog) render as a
    /// generic activity instead of crashing or hiding the user's log.
    static func activity(for id: String) -> WellbeingActivity {
        byID[id] ?? WellbeingActivity(
            id: id, name: "Activity", icon: "star",
            pointsPerMinute: 0.5, capMinutes: 60, presetMinutes: [10, 20, 30],
            why: ""
        )
    }

    static func isKnown(_ id: String) -> Bool { byID[id] != nil }
}
