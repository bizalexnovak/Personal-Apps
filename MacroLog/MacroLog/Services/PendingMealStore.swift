import Foundation

/// How a capture session was started. The capture screen branches on this for
/// its first phase (listen / photograph / go straight to analyzing).
enum CaptureMode: Equatable {
    case voice
    case scan
    case text(String)
}

/// Identifiable wrapper so the capture screen can be presented with
/// `.fullScreenCover(item:)` and re-presented for each new request.
struct CaptureRequest: Identifiable, Equatable {
    let id = UUID()
    let mode: CaptureMode
}

/// Hand-off between entry points (Siri intent, mic button, scan button, typed
/// field) and the app UI. Setting `request` presents the capture screen; the
/// screen clears it on dismiss.
@MainActor
final class PendingMealStore: ObservableObject {
    static let shared = PendingMealStore()

    @Published var request: CaptureRequest?

    func requestVoice() { request = CaptureRequest(mode: .voice) }
    func requestScan() { request = CaptureRequest(mode: .scan) }
    func requestText(_ text: String) { request = CaptureRequest(mode: .text(text)) }
}
