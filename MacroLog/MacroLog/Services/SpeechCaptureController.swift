import AVFoundation
import Foundation
import Speech

/// Owns the mic + speech-recognition session for CaptureView: requests
/// permissions, streams live partial transcripts, exposes an audio level for
/// the pulsing indicator, and auto-stops after ~2 s of silence.
@MainActor
final class SpeechCaptureController: ObservableObject {
    enum CaptureState: Equatable {
        case idle
        case requestingPermission
        case listening
        case captured            // transcript finalized — hand off to the pipeline
        case denied(String)      // permission problem — point at Settings
        case failed(String)      // transient problem — offer retry
    }

    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var audioLevel: Double = 0 // 0...1 for the pulse

    private let audioEngine = AVAudioEngine()
    // Failable locale-based init (the bare init() is non-optional) so the
    // guard in beginSession can surface "unavailable" as a real state.
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastSpeechAt = Date()

    /// Silence window after which listening auto-stops (once we've heard something).
    private let silenceCutoff: TimeInterval = 2.0
    /// Give up entirely if nothing at all is heard for this long.
    private let emptyCutoff: TimeInterval = 10.0

    // MARK: - Lifecycle

    func start() async {
        guard state != .listening, state != .requestingPermission else { return }
        state = .requestingPermission

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            state = .denied("MacroLog needs speech recognition permission to transcribe your meal. Enable it in Settings.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .denied("MacroLog needs microphone access to hear your meal. Enable it in Settings.")
            return
        }
        beginSession()
    }

    func restart() async {
        cleanup()
        transcript = ""
        state = .idle
        await start()
    }

    /// Manual "Done" button, and the silence auto-stop.
    func finishListening() {
        guard state == .listening else { return }
        cleanup()
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .failed("Didn't hear anything — try again.")
        } else {
            state = .captured
        }
    }

    func cancel() {
        cleanup()
        state = .idle
    }

    // MARK: - Session

    private func beginSession() {
        transcript = ""
        guard let recognizer, recognizer.isAvailable else {
            state = .failed("Speech recognition isn't available right now.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Bias recognition toward food/brand vocabulary the acoustic model
            // otherwise mangles ("Chobani" → "show bunny").
            request.contextualStrings = Self.foodVocabulary
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            // The tap runs on an audio thread — capture `request` locally and
            // hop to the main actor only for the published level.
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = SpeechCaptureController.rmsLevel(of: buffer)
                Task { @MainActor [weak self] in self?.audioLevel = level }
            }
            audioEngine.prepare()
            try audioEngine.start()

            lastSpeechAt = Date()
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in self?.handle(result: result, error: error) }
            }
            startSilenceTimer()
            state = .listening
        } catch {
            cleanup()
            state = .failed("Couldn't start the microphone: \(error.localizedDescription)")
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        guard state == .listening else { return }
        if let result {
            let text = result.bestTranscription.formattedString
            if text != transcript {
                transcript = text
                lastSpeechAt = Date()
            }
            if result.isFinal {
                finishListening()
                return
            }
        }
        if error != nil {
            // Recognizer errors mid-stream: keep whatever we heard; only fail
            // if there's nothing to keep.
            if transcript.isEmpty {
                cleanup()
                state = .failed("Didn't catch that — try again.")
            } else {
                finishListening()
            }
        }
    }

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkSilence() }
        }
    }

    private func checkSilence() {
        guard state == .listening else { return }
        let quietFor = Date().timeIntervalSince(lastSpeechAt)
        if !transcript.isEmpty, quietFor > silenceCutoff {
            finishListening()
        } else if transcript.isEmpty, quietFor > emptyCutoff {
            finishListening() // lands in .failed with the "didn't hear anything" message
        }
    }

    private func cleanup() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        audioLevel = 0
    }

    nonisolated private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames {
            sum += channel[i] * channel[i]
        }
        let rms = sqrt(sum / Float(frames))
        // Typical speech RMS is ~0.01-0.3; stretch into a visible 0...1 range.
        return min(1.0, Double(rms) * 8)
    }

    // MARK: - Recognition biasing

    /// Starter vocabulary for contextualStrings: brands, proteins, and units
    /// that generic dictation frequently misrecognizes.
    static let foodVocabulary: [String] = [
        // Brands
        "Chobani", "Fage", "Oikos", "Siggi's", "Yoplait", "Dannon", "Fairlife",
        "Quest", "Clif", "KIND", "RXBAR", "Premier Protein", "Muscle Milk",
        "Cheerios", "Special K", "Raisin Bran", "Quaker", "Nature Valley",
        "Skippy", "Jif", "Philadelphia", "Sargento", "Tillamook",
        "Oscar Mayer", "Butterball", "Jennie-O", "Hillshire Farm",
        "Starbucks", "Dunkin", "Chipotle", "Sweetgreen", "Panera", "Subway",
        "Chick-fil-A", "Halo Top", "La Croix", "Gatorade",
        // Proteins & common foods
        "turkey bacon", "chicken breast", "ground turkey", "ground beef",
        "pork chop", "ribeye", "sirloin", "salmon", "tuna", "shrimp",
        "tofu", "tempeh", "greek yogurt", "cottage cheese", "string cheese",
        "protein shake", "protein bar", "whey protein", "egg whites",
        "scrambled eggs", "hard boiled eggs", "overnight oats", "oatmeal",
        "granola", "avocado toast", "sourdough", "bagel", "tortilla",
        "quinoa", "brown rice", "white rice", "sweet potato", "edamame",
        "hummus", "peanut butter", "almond butter",
        // Units & amounts
        "ounce", "ounces", "tablespoon", "tablespoons", "teaspoon", "teaspoons",
        "cup", "cups", "slice", "slices", "piece", "pieces", "handful",
        "serving", "servings", "grams", "scoop", "scoops", "container", "packet",
    ]
}
