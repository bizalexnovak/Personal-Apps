import SwiftUI
import UIKit
import AVFoundation

/// Fire-the-shutter hook: the SwiftUI shutter button calls `fire()`, which the
/// camera controller wires to its photo capture. A tiny box (not @Published —
/// nothing observes it) so the representable can hand the trigger inward.
final class DishCameraTrigger: ObservableObject {
    var fire: () -> Void = {}
}

/// The Dish (AI estimate) capture surface: a live camera preview with a
/// deliberate shutter button — same always-on camera feel as the label
/// scanner, but the user decides the moment (framing a plate is a judgment
/// call, unlike a label the OCR can spot).
struct DishCameraScreen: View {
    var onCapture: (Data) -> Void

    @StateObject private var trigger = DishCameraTrigger()
    @State private var denied = false

    var body: some View {
        if denied {
            CaptureProblemView(
                message: "Foob needs camera access to photograph your dish. Enable it in Settings.",
                systemImage: "camera.fill"
            ) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ZStack {
                DishCameraView(
                    trigger: trigger,
                    onCapture: onCapture,
                    onDenied: { denied = true }
                )
                .ignoresSafeArea()

                VStack {
                    Text("Frame your dish, then tap the shutter for an AI nutrition estimate.")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 24)
                    Spacer()
                    shutterButton
                        // Clears the floating tab bar AND the mode switcher
                        // pinned above it.
                        .padding(.bottom, OrbNavBar.orbOnlyClearance + 64)
                }
                .padding()
            }
        }
    }

    private var shutterButton: some View {
        Button {
            trigger.fire()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(.white)
                    .frame(width: 58, height: 58)
            }
        }
        .accessibilityLabel("Take photo")
    }
}

/// UIKit half: AVCaptureSession + still-photo output behind the preview.
private struct DishCameraView: UIViewControllerRepresentable {
    @ObservedObject var trigger: DishCameraTrigger
    var onCapture: (Data) -> Void
    var onDenied: () -> Void

    func makeUIViewController(context: Context) -> DishCameraViewController {
        let vc = DishCameraViewController()
        vc.onCapture = onCapture
        vc.onDenied = onDenied
        trigger.fire = { [weak vc] in vc?.capturePhoto() }
        return vc
    }

    func updateUIViewController(_ vc: DishCameraViewController, context: Context) {
        // Rewire on updates in case the trigger object was recreated.
        trigger.fire = { [weak vc] in vc?.capturePhoto() }
    }
}

final class DishCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((Data) -> Void)?
    var onDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.alexnovak.foob.dishcamera")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var configured = false
    private var capturing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

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
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            onDenied?()
            return
        }
        session.addInput(input)
        session.addOutput(photoOutput)
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
        // Resume when the tab/mode is revisited (stopped on disappear).
        if configured, !session.isRunning {
            capturing = false
            queue.async { [weak self] in self?.session.startRunning() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto() {
        guard configured, !capturing else { return }
        capturing = true
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.7) else {
            capturing = false
            return
        }
        onCapture?(jpeg)
    }
}
