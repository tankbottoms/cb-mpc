import SwiftUI
import CryptoKit
import CoreImage.CIFilterBuiltins
#if os(iOS)
import UIKit
import AVFoundation
#endif

// MARK: - Pairing Entry Point

struct DevicePairingView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var pairingManager = PairingManager.shared

    @State private var selectedRole: PairingSession.PairingRole?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DEVICE PAIRING")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text("Pair two devices to enable true 2-party MPC. Each device holds one key share -- neither can sign alone.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.05))
                .cornerRadius(6)

                VStack(spacing: 12) {
                    Button(action: { selectedRole = .initiator }) {
                        HStack {
                            Image(systemName: "qrcode")
                                .font(.system(size: 24))
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Show QR Code")
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                Text("Display a QR code for the other device to scan")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button(action: { selectedRole = .joiner }) {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 24))
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Scan QR Code")
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                Text("Scan the QR code shown on the other device")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("HOW IT WORKS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    ForEach(Array([
                        "Both devices generate ephemeral X25519 key pairs",
                        "QR codes exchange public keys between devices",
                        "ECDH computes a shared secret (never transmitted)",
                        "6-digit PIN derived from shared secret -- verify on both screens",
                        "AES-256-GCM session key established for encrypted channel"
                    ].enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                                .frame(width: 16)
                            Text(step)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(.gray.opacity(0.05))
                .cornerRadius(6)

                Spacer()
            }
            .padding(16)
            .navigationTitle("Pair Device")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: Binding(
                get: { selectedRole.map { PairingRoleWrapper(role: $0) } },
                set: { selectedRole = $0?.role }
            )) { wrapper in
                PairingSessionView(role: wrapper.role, pairingManager: pairingManager, onComplete: {
                    selectedRole = nil
                    dismiss()
                })
            }
        }
    }
}

// Wrapper to make PairingRole identifiable for sheet
struct PairingRoleWrapper: Identifiable {
    let role: PairingSession.PairingRole
    var id: String { role == .initiator ? "initiator" : "joiner" }
}

// MARK: - Pairing Session View

struct PairingSessionView: View {
    let role: PairingSession.PairingRole
    let pairingManager: PairingManager
    let onComplete: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var session: PairingSession
    @State private var step: PairingStep = .showQR
    @State private var remoteName: String = ""
    @State private var pinConfirmed = false
    @State private var errorMessage: String?

    enum PairingStep {
        case showQR
        case scanRemote
        case confirmPIN
        case paired
    }

    init(role: PairingSession.PairingRole, pairingManager: PairingManager, onComplete: @escaping () -> Void) {
        self.role = role
        self.pairingManager = pairingManager
        self.onComplete = onComplete
        self._session = State(initialValue: PairingSession(role: role))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Step indicator
                HStack(spacing: 4) {
                    ForEach(0..<4) { i in
                        Capsule()
                            .fill(stepIndex >= i ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal, 16)

                switch step {
                case .showQR:
                    showQRView
                case .scanRemote:
                    scanRemoteView
                case .confirmPIN:
                    confirmPINView
                case .paired:
                    pairedView
                }
            }
            .navigationTitle(stepTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var stepIndex: Int {
        switch step {
        case .showQR: return 0
        case .scanRemote: return 1
        case .confirmPIN: return 2
        case .paired: return 3
        }
    }

    private var stepTitle: String {
        switch step {
        case .showQR: return role == .initiator ? "Show QR" : "Scan QR"
        case .scanRemote: return role == .initiator ? "Scan Response" : "Show Response"
        case .confirmPIN: return "Verify PIN"
        case .paired: return "Paired"
        }
    }

    // MARK: - Step Views

    private var showQRView: some View {
        VStack(spacing: 16) {
            if role == .initiator {
                Text("Show this QR code to the other device")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                qrCodeImage(for: session.initiatorQRPayload)

                Text("Session: \(session.sessionId.uuidString.prefix(8))...")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)

                Button("Other device scanned? Next") {
                    step = .scanRemote
                }
                .font(.system(size: 13, design: .monospaced))
                .buttonStyle(.borderedProminent)
            } else {
                Text("Scan the QR code shown on the other device")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                // Scanner
                #if os(iOS)
                PairingScannerView { data in
                    handleInitiatorQR(data)
                }
                .frame(height: 300)
                .cornerRadius(8)
                #else
                Text("Camera scanning requires iOS")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(height: 300)
                #endif
            }

            Spacer()
        }
        .padding(16)
    }

    private var scanRemoteView: some View {
        VStack(spacing: 16) {
            if role == .initiator {
                Text("Scan the response QR code from the other device")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                #if os(iOS)
                PairingScannerView { data in
                    handleJoinerQR(data)
                }
                .frame(height: 300)
                .cornerRadius(8)
                #else
                Text("Camera scanning requires iOS")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(height: 300)
                #endif
            } else {
                Text("Show this response QR to the initiating device")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                let responsePayload = joinerResponsePayload()
                qrCodeImage(for: responsePayload)

                Text("Session: \(session.sessionId.uuidString.prefix(8))...")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)

                Button("Other device scanned? Next") {
                    // Compute shared secret
                    if let remotePub = session.remotePublicKey {
                        do {
                            try session.computeSharedSecret(remotePublicKey: remotePub)
                            step = .confirmPIN
                        } catch {
                            errorMessage = "Key agreement failed: \(error.localizedDescription)"
                        }
                    }
                }
                .font(.system(size: 13, design: .monospaced))
                .buttonStyle(.borderedProminent)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding(16)
    }

    private var confirmPINView: some View {
        VStack(spacing: 24) {
            Text("Verify this PIN matches on both devices")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)

            if let pin = session.pin {
                HStack(spacing: 12) {
                    ForEach(Array(pin.enumerated()), id: \.offset) { _, digit in
                        Text(String(digit))
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .frame(width: 44, height: 56)
                            .background(.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }

            VStack(spacing: 8) {
                Text("Do the PINs match?")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("No, Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .buttonStyle(.bordered)

                    Button("Yes, Confirm") {
                        completePairing()
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .buttonStyle(.borderedProminent)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("SECURITY")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("This PIN was derived from an ECDH shared secret. If the PINs don't match, a man-in-the-middle attack may be in progress. Cancel immediately.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(.orange.opacity(0.05))
            .cornerRadius(6)

            Spacer()
        }
        .padding(16)
    }

    private var pairedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Device Paired")
                .font(.system(size: 18, weight: .bold, design: .monospaced))

            if !remoteName.isEmpty {
                Text(remoteName)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Encrypted channel established (AES-256-GCM)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("The paired device now appears in your Network tab.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(.green.opacity(0.05))
            .cornerRadius(6)

            Button("Done") {
                onComplete()
                dismiss()
            }
            .font(.system(size: 14, design: .monospaced))
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(16)
    }

    // MARK: - QR Handling

    private func handleInitiatorQR(_ data: Data) {
        // Parse: session_id(16) + pubkey(32) + name(variable)
        guard data.count >= 48 else {
            errorMessage = "Invalid QR code"
            return
        }

        let uuidBytes = data.prefix(16)
        let pubKeyBytes = data.subdata(in: 16..<48)
        let nameBytes = data.suffix(from: 48)

        // Store session ID from initiator
        let uuid = uuidBytes.withUnsafeBytes { ptr -> uuid_t in
            ptr.load(as: uuid_t.self)
        }
        session = PairingSession(role: .joiner)
        // Override session ID to match initiator
        // (We'll use a mutable copy approach)

        remoteName = String(data: nameBytes, encoding: .utf8) ?? "Unknown Device"

        guard let remotePub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: pubKeyBytes) else {
            errorMessage = "Invalid public key"
            return
        }
        session.remotePublicKey = remotePub

        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        #endif

        step = .scanRemote
    }

    private func handleJoinerQR(_ data: Data) {
        // Parse joiner response: pubkey(32) + name(variable)
        guard data.count >= 32 else {
            errorMessage = "Invalid response QR"
            return
        }

        let pubKeyBytes = data.prefix(32)
        let nameBytes = data.suffix(from: 32)

        remoteName = String(data: nameBytes, encoding: .utf8) ?? "Unknown Device"

        guard let remotePub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: pubKeyBytes) else {
            errorMessage = "Invalid public key"
            return
        }

        do {
            try session.computeSharedSecret(remotePublicKey: remotePub)
            #if os(iOS)
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            #endif
            step = .confirmPIN
        } catch {
            errorMessage = "Key agreement failed"
        }
    }

    private func joinerResponsePayload() -> Data {
        var payload = Data()
        payload.append(session.localKeyPair.publicKey.rawRepresentation)
        #if os(iOS)
        let deviceName = UIDevice.current.name
        #else
        let deviceName = Host.current().localizedName ?? "Mac"
        #endif
        payload.append(Data(deviceName.utf8))
        return payload
    }

    private func completePairing() {
        let device = PairedDevice(
            id: UUID(),
            name: remoteName.isEmpty ? "Paired Device" : remoteName,
            deviceModel: "iPhone",
            publicKey: session.remotePublicKey?.rawRepresentation ?? Data(),
            pairedAt: Date(),
            lastSeenAt: Date(),
            isOnline: false,
            shareCount: 0
        )
        pairingManager.addPairedDevice(device)

        #if os(iOS)
        let success = UINotificationFeedbackGenerator()
        success.notificationOccurred(.success)
        #endif

        step = .paired
    }

    // MARK: - QR Code Image

    @ViewBuilder
    private func qrCodeImage(for data: Data) -> some View {
        let base64 = data.base64EncodedString()
        let ciContext = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let _ = {
            filter.message = Data(base64.utf8)
            filter.correctionLevel = "M"
        }()

        if let output = filter.outputImage,
           output.extent.size.width > 0 {
            let scale = 200.0 / output.extent.size.width
            let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            if let cgImage = ciContext.createCGImage(transformed, from: transformed.extent) {
                Image(uiImage: UIImage(cgImage: cgImage))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(12)
                    .background(.white)
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Pairing QR Scanner (reuses camera infra)

#if os(iOS)
struct PairingScannerView: UIViewControllerRepresentable {
    let onScan: (Data) -> Void

    func makeUIViewController(context: Context) -> PairingScannerVC {
        let vc = PairingScannerVC()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ vc: PairingScannerVC, context: Context) {
        vc.onScan = onScan
    }
}

class PairingScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((Data) -> Void)?
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didCapture = false

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
        captureSession.stopRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didCapture else { return }
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  readable.type == .qr,
                  let stringValue = readable.stringValue,
                  let data = Data(base64Encoded: stringValue) else { continue }
            didCapture = true
            captureSession.stopRunning()
            onScan?(data)
            return
        }
    }
}
#endif
