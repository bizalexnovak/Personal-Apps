import Foundation

/// Hand-off flag between the Siri intent and the app UI. The intent no longer
/// carries any text — it just asks the app to open the voice capture screen,
/// where the app records and transcribes the meal itself.
@MainActor
final class PendingMealStore: ObservableObject {
    static let shared = PendingMealStore()

    @Published var voiceCaptureRequested = false

    func requestVoiceCapture() {
        voiceCaptureRequested = true
    }

    /// Returns whether a capture was requested, clearing the flag.
    func consumeVoiceCaptureRequest() -> Bool {
        defer { voiceCaptureRequested = false }
        return voiceCaptureRequested
    }
}
