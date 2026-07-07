import Foundation

/// Hand-off buffer between the Siri intent and the app UI. The intent writes
/// the raw transcript here and opens the app; ContentView consumes it and
/// starts the capture flow (including clarification cards).
@MainActor
final class PendingMealStore: ObservableObject {
    static let shared = PendingMealStore()

    @Published var pendingText: String?

    func submit(_ text: String) {
        pendingText = text
    }

    /// Returns and clears the pending transcript, if any.
    func consume() -> String? {
        defer { pendingText = nil }
        return pendingText
    }
}
