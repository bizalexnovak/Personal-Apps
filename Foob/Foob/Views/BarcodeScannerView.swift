import SwiftUI
import UIKit
import AVFoundation

/// The full-screen barcode scan surface: live camera with auto-detect for
/// EAN-8, EAN-13, and UPC-A barcodes. Shows an optional notice banner (e.g.
/// "product not found — try the label scan") without leaving the scanner.
struct BarcodeScannerScreen: View {
    var notice: String?
    var onScan: (String) -> Void
    @State private var denied = false

    var body: some View {
        if denied {
            CaptureProblemView(
                message: "Foob needs camera access to scan barcodes. Enable it in Settings.",
                systemImage: "camera.fill"
            ) {
                Button("OPEN SETTINGS") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(GhostCapsule(gold: true))
            }
        } else {
            ZStack {
                Lux.cameraGround.ignoresSafeArea()
                BarcodeScannerCameraView(onScan: onScan, onDenied: { denied = true })
                    .ignoresSafeArea()
                VStack(spacing: 18) {
                    if let notice {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 10))
                            Text(notice.uppercased())
                                .font(Lux.smallcaps(9))
                                .tracking(1.5)
                        }
                        .foregroundStyle(Lux.ground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Lux.ember))
                        .padding(.top, 8)
                    }
                    Spacer()
                    ZStack {
                        CornerBrackets(size: CGSize(width: 270, height: 170), leg: 30)
                        Image(systemName: "barcode")
                            .font(.system(size: 46, weight: .ultraLight))
                            .foregroundStyle(Lux.cream.opacity(0.5))
                    }
                    .frame(width: 270, height: 170)
                    Text("Center the barcode — it reads on its own.")
                        .font(Lux.serifItalic(15))
                        .foregroundStyle(Lux.cream.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.7), radius: 6)
                    Spacer()
                }
                .padding(.horizontal, Lux.hPad)
            }
        }
    }
}

private struct BarcodeScannerCameraView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onDenied: () -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.onScan = onScan
        vc.onDenied = onDenied
        return vc
    }

    func updateUIViewController(_ vc: BarcodeScannerViewController, context: Context) {}
}

final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.alexnovak.foob.barcode")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var scanned = false
    private var configured = false

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
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            onDenied?()
            return
        }
        session.addInput(input)

        let metaOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metaOutput) else {
            session.commitConfiguration()
            onDenied?()
            return
        }
        session.addOutput(metaOutput)
        // Delegate must be set AFTER adding to session so metadata types are valid.
        metaOutput.setMetadataObjectsDelegate(self, queue: .main)
        metaOutput.metadataObjectTypes = [.ean8, .ean13, .upce]
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
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
        // Called when the coordinator returns "not found" and the scanner
        // comes back into view — reset so the user can try another barcode.
        if configured, !session.isRunning {
            scanned = false
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

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !scanned,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        scanned = true
        queue.async { [weak self] in self?.session.stopRunning() }
        onScan?(value)
    }
}
