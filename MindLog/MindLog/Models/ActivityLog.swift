import Foundation
import SwiftData

/// One logged wellbeing activity — "meditated 20 minutes", "45-minute walk".
/// `activityID` keys into `ActivityCatalog`; logs whose activity is ever
/// removed from the catalog still render via the catalog's fallback entry.
@Model
final class ActivityLog {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var activityID: String
    var minutes: Double
    var note: String

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        activityID: String,
        minutes: Double,
        note: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.activityID = activityID
        self.minutes = minutes
        self.note = note
    }

    var activity: WellbeingActivity { ActivityCatalog.activity(for: activityID) }

    /// Points this log contributes before the per-activity daily cap is
    /// applied (capping needs the whole day — see `PracticeScore`).
    var uncappedPoints: Double { activity.pointsPerMinute * minutes }
}
