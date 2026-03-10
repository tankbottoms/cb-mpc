import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
#endif

struct QRScannerView: View {
    let onComplete: ([Data]) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var scannedParts: [Int: Data] = [:]
    @State private var totalParts: Int = 0
    @State private var lastScannedPart: Int = -1
    @State private var errorMessage: String?
    @State private var isComplete = false

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreviewView(onQRDetected: handleQRCode)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    VStack(spacing: 8) {
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.red)
                                .padding(8)
                                .background(.red.opacity(0.1))
                                .cornerRadius(6)
                        }

                        if totalParts > 0 {
                            Text("\(scannedParts.count) of \(totalParts) parts scanned")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)

                            HStack(spacing: 6) {
                                ForEach(0..<totalParts, id: \.self) { index in
                                    Circle()
                                        .fill(scannedParts[index] != nil ? Color.green : Color.white.opacity(0.3))
                                        .frame(width: 10, height: 10)
                                }
                            }

                            if scannedParts.count < totalParts {
                                Text("Hold steady — QR codes cycle automatically")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        } else {
                            VStack(spacing: 4) {
                                Text("Point camera at the rotating QR codes")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("Each part will be captured automatically")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    .padding(16)
                    .background(.black.opacity(0.7))
                    .cornerRadius(12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func handleQRCode(_ data: Data) {
        guard !isComplete else { return }

        // Validate CBMPC magic header: 0x43 0x42 0x4D 0x50 0x43
        let magic: [UInt8] = [0x43, 0x42, 0x4D, 0x50, 0x43]
        guard data.count >= 10 else { return }
        guard Array(data.prefix(5)) == magic else {
            errorMessage = "Not a CB-MPC QR code"
            return
        }

        errorMessage = nil
        let partNumber = Int(data.readUInt16BE(at: 6))
        let total = Int(data.readUInt16BE(at: 8))

        if totalParts == 0 {
            totalParts = total
        }

        guard total == totalParts else {
            errorMessage = "QR code set mismatch"
            return
        }

        guard scannedParts[partNumber] == nil else { return }

        scannedParts[partNumber] = data
        lastScannedPart = partNumber

        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        #endif

        if scannedParts.count == totalParts {
            isComplete = true

            #if os(iOS)
            let success = UINotificationFeedbackGenerator()
            success.notificationOccurred(.success)
            #endif

            let ordered = (0..<totalParts).compactMap { scannedParts[$0] }
            onComplete(ordered)
            dismiss()
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewControllerRepresentable {
    let onQRDetected: (Data) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onQRDetected = onQRDetected
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.onQRDetected = onQRDetected
    }
}

class CameraViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onQRDetected: ((Data) -> Void)?
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastProcessedString: String?
    private var processedStrings: Set<String> = []
    private var isStopped = false

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds
        if let layer = previewLayer {
            view.layer.addSublayer(layer)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    func stopSession() {
        guard !isStopped else { return }
        isStopped = true
        captureSession.stopRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !isStopped else { return }
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  readable.type == .qr,
                  let stringValue = readable.stringValue else { continue }
            // Deduplicate at the camera level — don't re-process the same QR content
            guard !processedStrings.contains(stringValue) else { continue }
            guard let data = Data(base64Encoded: stringValue) else { continue }
            processedStrings.insert(stringValue)
            onQRDetected?(data)
        }
    }
}
