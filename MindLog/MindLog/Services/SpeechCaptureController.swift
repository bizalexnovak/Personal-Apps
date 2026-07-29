import AVFoundation
import Foundation
import Speech

/// Last audio level forwarded to the main actor. Kept outside the controller
/// (which is @MainActor) so it carries no actor isolation — it's only ever
/// read/written on the mic tap's serial dispatch queue.
private final class SentLevelBox {
    var value: Double = -1
}

/// Owns the mic + speech-recognition session for the voice journal: requests
/// permissions, streams live partial transcripts, exposes an audio level for
/// the pulsing indicator, and auto-stops after a stretch of silence. Tuned for
/// journaling rather than command capture: the silence window is generous
/// (people pause to think mid-entry), dictation punctuation is on, and the
/// vocabulary bias leans toward feeling words.
@MainActor
final class SpeechCaptureController: ObservableObject {
    enum CaptureState: Equatable {
        case idle
        case requestingPermission
        case listening
        case captured            // transcript finalized — hand off to review
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
    /// Set (sticky for this app run) after an on-device-only session errors
    /// before hearing anything — the usual sign the locale claims on-device
    /// support but the model assets were never downloaded. Subsequent sessions
    /// use server-based recognition instead of failing forever.
    private var preferServerRecognition = false

    /// Silence window after which listening auto-stops (once we've heard
    /// something). Journaling pauses run long — don't cut a thought off.
    private let silenceCutoff: TimeInterval = 4.0
    /// Give up entirely if nothing at all is heard for this long.
    private let emptyCutoff: TimeInterval = 12.0

    // MARK: - Lifecycle

    func start() async {
        guard state != .listening, state != .requestingPermission else { return }
        state = .requestingPermission

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            state = .denied("MindLog needs speech recognition permission to transcribe your journal. Enable it in Settings.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .denied("MindLog needs microphone access to hear you. Enable it in Settings.")
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
        transcript = ""
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
            // Long-form dictation with automatic punctuation — a journal
            // entry should read like prose, not a run-on transcript.
            request.taskHint = .dictation
            request.addsPunctuation = true
            // Keep transcription working with zero signal: prefer on-device
            // recognition when the locale supports it (it's also the private
            // path — audio never leaves the phone). `supportsOnDeviceRecognition`
            // only reports LOCALE capability, not whether the on-device model
            // is actually downloaded — if an on-device session errors with
            // nothing heard, `preferServerRecognition` is set and this app run
            // falls back to server-based recognition (see handle(result:error:)).
            if recognizer.supportsOnDeviceRecognition, !preferServerRecognition {
                request.requiresOnDeviceRecognition = true
            }
            // Bias recognition toward the vocabulary of journaling.
            request.contextualStrings = Self.journalVocabulary
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            // The tap runs on an audio thread — capture `request` locally and
            // hop to the main actor only for the published level. The level is
            // quantized to 0.05 steps and unchanged values are dropped at the
            // source: buffers arrive ~45×/s and every publish re-renders the
            // observing capture screen, so silence would otherwise spam the
            // main thread with no visible change. (`lastSent` is only touched
            // on the tap's serial queue.)
            let lastSent = SentLevelBox()
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = (SpeechCaptureController.rmsLevel(of: buffer) * 20).rounded() / 20
                guard level != lastSent.value else { return }
                lastSent.value = level
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
                // An on-device session that dies before hearing anything is
                // usually a missing on-device model — retry once via server
                // instead of showing "didn't catch that" forever. (If the
                // device is offline too, the server session errors with
                // requiresOnDeviceRecognition false and falls through to the
                // normal failure below — no retry loop.)
                if request?.requiresOnDeviceRecognition == true, !preferServerRecognition {
                    preferServerRecognition = true
                    Task { await restart() }
                    return
                }
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

    /// Vocabulary for contextualStrings: feeling words, practice names, and
    /// the phrases people actually open a diary with.
    static let journalVocabulary: [String] = [
        // Feelings
        "anxious", "anxiety", "overwhelmed", "burned out", "burnout",
        "stressed", "stress", "grateful", "gratitude", "content", "calm",
        "restless", "lonely", "irritable", "hopeful", "drained", "energized",
        "frustrated", "proud", "ashamed", "guilty", "excited", "nervous",
        "panic attack", "intrusive thoughts", "ruminating", "self-care",
        // Practices & context
        "meditated", "meditation", "therapy", "therapist", "journaling",
        "breathing exercise", "box breathing", "mindfulness", "mindful",
        "yoga", "gym", "workout", "a walk outside", "slept badly", "slept well",
        "insomnia", "doomscrolling", "screen time",
        // Openers
        "today I", "I feel", "I felt", "I'm feeling", "on my mind",
        "I noticed", "I keep thinking about",
    ]
}
