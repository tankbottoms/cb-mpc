import SwiftUI
import CoreImage.CIFilterBuiltins
import CryptoKit
#if os(iOS)
import UIKit
#endif

struct ExportKeySheetView: View {
    let key: ManagedKey
    let exportJSON: String
    let utcFileName: String
    let exportFormatLabel: String
    let exportDataForFormat: String

    @EnvironmentObject var keyStore: KeyStore
    @Environment(\.dismiss) var dismiss

    @State private var exportedToSecureEnclave = false
    @State private var exportedToICloudKeychain = false
    @State private var exportedToStorage = false
    @State private var exportStatusMessage: String?
    @State private var copiedId: String?

    // QR state — populated by .task
    @State private var multiQRImages: [UIImage] = []
    @State private var multiQRPartCount: Int = 0
    @State private var multiQRCurrentPart: Int = 0
    @State private var multiQRPlaying = true
    @State private var multiQRPassphrase: String = ""
    @State private var multiQRElapsed: Double = 0
    @State private var qrReady = false

    @AppStorage("qrTransferSpeed") private var qrTransferSpeed: Double = 1.5

    private var exportTimeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // QR code section
                    if qrReady, !multiQRImages.isEmpty {
                        let safeIndex = min(multiQRCurrentPart, multiQRImages.count - 1)
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Image(uiImage: multiQRImages[safeIndex])
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 200, height: 200)
                                    .padding(12)
                                    .background(.white)
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        if multiQRPartCount > 1 {
                                            multiQRPlaying.toggle()
                                        }
                                    }

                                if multiQRPartCount > 1 {
                                    Text(multiQRPlaying ? "Tap to pause" : "Tap to resume")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)

                                    Text("Part \(safeIndex + 1) of \(multiQRPartCount)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))

                                    HStack(spacing: 6) {
                                        ForEach(0..<multiQRPartCount, id: \.self) { index in
                                            Circle()
                                                .fill(index == safeIndex ? Color.blue : Color.gray.opacity(0.3))
                                                .frame(width: 8, height: 8)
                                                .onTapGesture {
                                                    multiQRCurrentPart = index
                                                    multiQRElapsed = 0
                                                }
                                        }
                                    }

                                    Button {
                                        dismiss()
                                        NotificationCenter.default.post(name: .switchToSettingsTab, object: nil)
                                    } label: {
                                        Text("Cycle speed: \(String(format: "%.1f", qrTransferSpeed))s -- change in Settings > QR Transfer")
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(.blue.opacity(0.7))
                                            .underline()
                                    }
                                }
                            }
                            Spacer()
                        }
                    } else {
                        HStack {
                            Spacer()
                            ProgressView("Encoding...")
                                .padding()
                            Spacer()
                        }
                    }

                    // UTC filename
                    VStack(spacing: 0) {
                        let parts = utcFileName.components(separatedBy: "--")
                        if parts.count >= 3 {
                            Text("\(parts[0])--\(parts[1])--")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("\(parts[2]).json")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(utcFileName).json")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Text("EXPORT DATA (\(exportFormatLabel.uppercased()))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        copyButton(exportDataForFormat, id: "export")
                    }

                    Text(exportDataForFormat)
                        .font(.system(size: 9, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(4)

                    // Status message
                    if let msg = exportStatusMessage {
                        Text(msg)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.blue)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.blue.opacity(0.05))
                            .cornerRadius(4)
                    }

                    // Backup destinations
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BACKUP TO")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)

                        ForEach(ExportDestination.allCases, id: \.rawValue) { dest in
                            let exported = isDestinationExported(dest)
                            Button(action: {
                                handleExportDestination(dest)
                            }) {
                                HStack {
                                    Image(systemName: exported ? "checkmark.circle.fill" : dest.icon)
                                        .font(.system(size: 14))
                                        .foregroundColor(exported ? .blue : .primary)
                                        .frame(width: 24)
                                    Text(dest.rawValue)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(exported ? .blue : .primary)
                                    Spacer()
                                    if !exported {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(10)
                                .background(exported ? .blue.opacity(0.05) : .gray.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Transfer passphrase
                    if !multiQRPassphrase.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TRANSFER PASSPHRASE")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                            HStack {
                                Text(multiQRPassphrase)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                copyButton(multiQRPassphrase, id: "passphrase")
                            }
                            .padding(8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Export Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await generateQRCodes()
            }
            .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
                guard multiQRPlaying, multiQRPartCount > 1, qrReady else { return }
                multiQRElapsed += 0.1
                if multiQRElapsed >= qrTransferSpeed {
                    multiQRElapsed = 0
                    multiQRCurrentPart = (multiQRCurrentPart + 1) % multiQRPartCount
                }
            }
        }
    }

    // MARK: - QR Generation

    @MainActor
    private func generateQRCodes() async {
        // Generate passphrase
        let randomBytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        multiQRPassphrase = Data(randomBytes).base64EncodedString().prefix(16).description

        let jsonData = Data(exportJSON.utf8)
        let passphrase = multiQRPassphrase

        // Encode parts (inline — MultiQRCodec.encode crashes in Release due to CryptoKit slice bug)
        let parts: [Data]
        do {
            parts = try Self.encodeForQR(json: jsonData, passphrase: passphrase)
        } catch {
            exportStatusMessage = "QR error: \(error.localizedDescription)"
            return
        }

        // Generate QR images
        var images: [UIImage] = []
        let ciContext = CIContext()
        for part in parts {
            let filter = CIFilter.qrCodeGenerator()
            let base64String = part.base64EncodedString()
            filter.message = base64String.data(using: .ascii)!
            filter.correctionLevel = "L"
            if let output = filter.outputImage,
               output.extent.size.width > 0 {
                let scale = 200.0 / output.extent.size.width
                let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                if let cgImage = ciContext.createCGImage(transformed, from: transformed.extent) {
                    images.append(UIImage(cgImage: cgImage))
                }
            }
        }

        guard !images.isEmpty else {
            exportStatusMessage = "Failed to generate QR codes"
            return
        }

        multiQRImages = images
        multiQRPartCount = images.count
        multiQRCurrentPart = 0
        qrReady = true
    }

    // MARK: - QR Encode (workaround for CryptoKit SealedBox slice crash in Release builds)

    private static let magic: [UInt8] = [0x43, 0x42, 0x4D, 0x50, 0x43]
    private static let ver: UInt8 = 1
    private static let hdrSize = 10
    private static let p0Extra = 22
    private static let maxQR = 450   // ~450 bytes binary → ~600 chars base64 → QR version 9-10 (easy to scan)

    private static func encodeForQR(json: Data, passphrase: String) throws -> [Data] {
        let checksum = MultiQRCodec.crc32Checksum(json)

        let nsData = json as NSData
        guard let compressed = try? nsData.compressed(using: .zlib) as Data else {
            throw MultiQRCodec.CodecError.compressionFailed
        }

        let salt = Data("CBMPC-MultiQR-v1".utf8)
        let inputKey = SymmetricKey(data: Data(passphrase.utf8))
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: inputKey, salt: salt, outputByteCount: 32)
        let nonce = AES.GCM.Nonce()
        guard let sealedBox = try? AES.GCM.seal(compressed, using: key, nonce: nonce) else {
            throw MultiQRCodec.CodecError.encryptionFailed
        }

        // FIX: Explicitly copy into fresh contiguous Data.
        // sealedBox.ciphertext + sealedBox.tag crashes when subscripted in Release builds
        // due to CryptoKit returning internal slices with non-zero startIndex.
        var encrypted = Data(sealedBox.ciphertext)
        encrypted.append(contentsOf: sealedBox.tag)

        let p0Max = maxQR - hdrSize - p0Extra
        let numParts = max(1, Int(ceil(Double(encrypted.count) / Double(p0Max))))
        let baseChunk = encrypted.count / numParts
        let remainder = encrypted.count % numParts
        var chunks: [Data] = []
        var off = 0
        for i in 0..<numParts {
            let thisChunk = baseChunk + (i < remainder ? 1 : 0)
            let end = off + thisChunk
            chunks.append(Data(encrypted[off..<end]))
            off = end
        }

        let totalParts = UInt16(chunks.count)
        let nonceBytes = nonce.withUnsafeBytes { Data($0) }
        let origSize = UInt32(json.count)

        var parts: [Data] = []
        for (i, chunk) in chunks.enumerated() {
            var frame = Data()
            frame.append(contentsOf: magic)
            frame.append(ver)
            frame.appendUInt16BE(UInt16(i))
            frame.appendUInt16BE(totalParts)
            if i == 0 {
                frame.append(1) // zlib
                frame.append(1) // AES-256-GCM
                frame.appendUInt32BE(origSize)
                frame.append(nonceBytes)
                frame.appendUInt32BE(checksum)
            }
            frame.append(chunk)
            parts.append(frame)
        }
        return parts
    }

    // MARK: - Export Destinations

    private func isDestinationExported(_ dest: ExportDestination) -> Bool {
        switch dest {
        case .secureEnclave: return exportedToSecureEnclave
        case .icloudKeychain: return exportedToICloudKeychain
        case .storage: return exportedToStorage
        }
    }

    private func handleExportDestination(_ dest: ExportDestination) {
        switch dest {
        case .secureEnclave:
            let jsonData = Data(exportJSON.utf8)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "export_\(key.id.uuidString)",
                kSecAttrService as String: "xyz.atsignhandle.cb-mpc.keystore",
                kSecValueData as String: jsonData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            SecItemDelete(query as CFDictionary)
            let status = SecItemAdd(query as CFDictionary, nil)
            if status == errSecSuccess {
                #if os(iOS)
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                #endif
                withAnimation {
                    exportedToSecureEnclave = true
                    exportStatusMessage = "\(utcFileName).json saved to Device Keychain at \(exportTimeString)"
                }
            }

        case .icloudKeychain:
            let jsonData = Data(exportJSON.utf8)
            let status = KeychainSyncManager.save(keystoreJSON: jsonData, keyId: key.id)
            if status == errSecSuccess {
                #if os(iOS)
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                #endif
                withAnimation {
                    exportedToICloudKeychain = true
                    exportStatusMessage = "\(utcFileName).json synced to iCloud Keychain at \(exportTimeString)"
                }
            } else {
                withAnimation {
                    exportStatusMessage = "iCloud Keychain sync failed (status \(status))"
                }
            }

        case .storage:
            let jsonData = Data(exportJSON.utf8)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(utcFileName).json")
            try? jsonData.write(to: tempURL, options: .atomic)
            #if os(iOS)
            let av = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                var topVC = rootVC
                while let presented = topVC.presentedViewController { topVC = presented }
                if let popover = av.popoverPresentationController {
                    popover.sourceView = topVC.view
                    popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                topVC.present(av, animated: true)
            }
            #endif
            withAnimation {
                exportedToStorage = true
                exportStatusMessage = "\(utcFileName).json exported via File Export at \(exportTimeString)"
            }
        }
    }

    @ViewBuilder
    private func copyButton(_ text: String, id: String) -> some View {
        Button(action: {
            #if os(iOS)
            UIPasteboard.general.string = text
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            #endif
            copiedId = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedId == id { copiedId = nil }
            }
        }) {
            Image(systemName: copiedId == id ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundColor(copiedId == id ? .blue : .secondary)
        }
        .buttonStyle(.plain)
    }
}
