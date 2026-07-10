import SwiftUI
import UIKit
import AVFoundation
import CoreImage
import Vision

/// A live camera scanner that reads nutrition labels straight from the video
/// feed — no shutter. It runs on-device text recognition on the preview frames
/// and, once it sees enough nutrition-label wording ("Nutrition Facts",
/// "Calories", "Serving…"), auto-grabs that frame as a JPEG and hands it off.
/// Tapping the preview force-captures the current frame as a fallback.
struct LiveLabelScannerView: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    var onDenied: () -> Void

    func makeUIViewController(context: Context) -> LabelScannerViewController {
        let vc = LabelScannerViewController()
        vc.onCapture = onCapture
        vc.onDenied = onDenied
        return vc
    }

    func updateUIViewController(_ vc: LabelScannerViewController, context: Context) {}
}

final class LabelScannerViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onCapture: ((Data) -> Void)?
    var onDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.alexnovak.macrolog.scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let ciContext = CIContext()

    private lazy var textRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast       // fast enough for a live feed
        request.usesLanguageCorrection = false
        return request
    }()

    private var lastAnalysis = Date.distantPast
    private var labelHits = 0        // consecutive frames that look like a label
    private var captured = false     // guard: only hand off once
    private var forceCapture = false // set by a tap
    private var configured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configure() } else { self?.onDenied?() }
                }
            }
        default:
            onDenied?()
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            onDenied?()
            return
        }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        if let connection = preview.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
        configured = true

        queue.async { [weak self] in self?.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Resume when the tab is revisited (the session is stopped on disappear).
        if configured, !captured, !session.isRunning {
            queue.async { [weak self] in self?.session.startRunning() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stop()
    }

    private func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    @objc private func handleTap() { forceCapture = true }

    // MARK: - Frame processing

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !captured, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if forceCapture {
            handOff(pixelBuffer)
            return
        }

        // Throttle OCR so we don't chew battery on every frame.
        let now = Date()
        guard now.timeIntervalSince(lastAnalysis) > 0.35 else { return }
        lastAnalysis = now

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do { try handler.perform([textRequest]) } catch { return }

        let lines = (textRequest.results ?? []).compactMap {
            ($0 as? VNRecognizedTextObservation)?.topCandidates(1).first?.string
        }
        let text = lines.joined(separator: " ").lowercased()

        if Self.looksLikeLabel(text) {
            labelHits += 1
        } else {
            labelHits = max(0, labelHits - 1)
        }
        // Two good frames in a row → confident it's a real label, not a fluke.
        if labelHits >= 2 {
            handOff(pixelBuffer)
        }
    }

    /// Heuristic: "Nutrition Facts" alone is decisive; otherwise require two
    /// independent label signals so a random word doesn't trigger a capture.
    static func looksLikeLabel(_ text: String) -> Bool {
        if text.contains("nutrition facts") { return true }
        let signals = [
            text.contains("calorie"),
            text.contains("serving"),
            text.contains("daily value") || text.contains("% dv") || text.contains("amount per"),
            text.contains("total fat") || text.contains("sodium") || text.contains("carbohydrate"),
        ].filter { $0 }.count
        return signals >= 2
    }

    private func handOff(_ pixelBuffer: CVPixelBuffer) {
        captured = true
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8) else {
            captured = false
            return
        }
        stop()
        DispatchQueue.main.async { [weak self] in self?.onCapture?(data) }
    }
}
