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

/// Hand-off from Siri / deep links to the modal capture screen. Setting
/// `request` presents CaptureView; the screen clears it on dismiss. In-app
/// capture instead routes through `CaptureHub` to the Log tab (see below).
@MainActor
final class PendingMealStore: ObservableObject {
    static let shared = PendingMealStore()

    @Published var request: CaptureRequest?

    func requestVoice() { request = CaptureRequest(mode: .voice) }
    func requestScan() { request = CaptureRequest(mode: .scan) }
    func requestText(_ text: String) { request = CaptureRequest(mode: .text(text)) }
}

/// In-app capture routing. The tab bar's global "+" menu and the Log tab's own
/// switcher both go through here so capture always happens inline on the Log
/// tab (no modal). `AppTab` indexes the custom tab bar's selection.
enum AppTab {
    static let log = 0
    static let today = 1
    static let trends = 2
    static let settings = 3
}

enum LogCaptureMode: String, CaseIterable, Identifiable, Equatable {
    case voice, scan, dish
    var id: String { rawValue }
    var title: String {
        switch self {
        case .voice: return "Voice"
        case .scan: return "Scan"
        case .dish: return "AI"
        }
    }
    var menuIcon: String {
        switch self {
        case .voice: return "mic.fill"
        case .scan: return "doc.viewfinder"
        case .dish: return "sparkles"
        }
    }
}

@MainActor
final class CaptureHub: ObservableObject {
    /// Shared so Siri intents (which run in-process before the UI exists) can
    /// route capture to the Log tab the same way the in-app "+" menu does.
    static let shared = CaptureHub()

    /// Which tab is showing (bound to the custom tab bar's selection). The app
    /// opens on the Log tab.
    @Published var selectedTab = AppTab.log
    /// The active mode on the Log tab.
    @Published var logMode: LogCaptureMode = .voice
    /// One-shot flags the Log tab consumes after switching in.
    @Published var autoStartVoice = false
    @Published var openType = false

    /// True when a Siri/deep-link action is queued at launch — used to skip the
    /// welcome splash so the action starts immediately.
    var hasPendingLaunchAction: Bool {
        autoStartVoice || openType || logMode == .scan
    }

    func goVoice() {
        logMode = .voice
        autoStartVoice = true
        selectedTab = AppTab.log
    }

    func goScan() {
        logMode = .scan
        selectedTab = AppTab.log
    }

    func goDish() {
        logMode = .dish
        selectedTab = AppTab.log
    }

    func goType() {
        openType = true
        selectedTab = AppTab.log
    }
}
