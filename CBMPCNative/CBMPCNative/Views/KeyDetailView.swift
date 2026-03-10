import SwiftUI
import CryptoKit
import CoreImage.CIFilterBuiltins
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum KeyDetailSheet: Identifiable {
    case signing, signTx, verify, qrShare, derive, export, coSigner
    var id: Int {
        switch self {
        case .signing: return 0
        case .signTx: return 1
        case .verify: return 2
        case .qrShare: return 3
        case .derive: return 4
        case .export: return 5
        case .coSigner: return 6
        }
    }
}

struct KeyDetailView: View {
    let key: ManagedKey
    @EnvironmentObject var keyStore: KeyStore
    @State private var activeSheet: KeyDetailSheet?
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var copiedId: String?
    @State private var navigateToDerivedKeyId: UUID?
    @AppStorage("exportFormat") private var exportFormat = "keystoreJSON"
    @AppStorage("qrTransferSpeed") private var qrTransferSpeed: Double = 1.5

    private var hasKeyData: Bool {
        UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") != nil
    }

    private var publicKeyFirstPart: String {
        let pk = key.publicKey
        let splitPoint = pk.index(pk.startIndex, offsetBy: pk.count * 3 / 4, limitedBy: pk.endIndex) ?? pk.endIndex
        return String(pk[pk.startIndex..<splitPoint])
    }

    private var publicKeySecondPart: String {
        let pk = key.publicKey
        let splitPoint = pk.index(pk.startIndex, offsetBy: pk.count * 3 / 4, limitedBy: pk.endIndex) ?? pk.endIndex
        return String(pk[splitPoint..<pk.endIndex])
    }

    /// Plain 0x-prefixed public key for QR share
    private var publicKeyHex: String {
        "0x\(key.publicKey)"
    }

    private func buildKeystoreDict() -> [String: Any] {
        var cbmpc: [String: Any] = [
            "name": key.name,
            "publicKey": key.publicKey,
            "keyType": key.keyType.rawValue,
            "curveCode": Int(key.curveCode),
            "createdAt": ISO8601DateFormatter().string(from: key.createdAt),
            "storageLocation": key.storageLocation.rawValue
        ]
        if let path = key.derivationPath {
            cbmpc["derivationPath"] = path
        }
        if let parentId = key.parentKeyId {
            cbmpc["parentKeyId"] = parentId.uuidString
        }
        if exportFormat == "keystoreJSON" {
            if let keyData = UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") {
                cbmpc["keyData"] = keyData.base64EncodedString()
            }
        }

        let dict: [String: Any] = [
            "version": 3,
            "id": key.id.uuidString.lowercased(),
            "address": String(key.publicKey.suffix(40)),
            "crypto": [
                "cipher": "aes-128-ctr",
                "cipherparams": ["iv": ""],
                "ciphertext": "",
                "kdf": "scrypt",
                "kdfparams": [
                    "dklen": 32,
                    "n": 262144,
                    "p": 1,
                    "r": 8,
                    "salt": ""
                ],
                "mac": ""
            ],
            "cb-mpc": cbmpc
        ]
        return dict
    }

    private var utcFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let timestamp = formatter.string(from: key.createdAt)
        let addr = String(key.publicKey.suffix(40))
        return "UTC--\(timestamp)--\(addr)"
    }

    private var exportJSON: String {
        let dict = buildKeystoreDict()
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    /// Compact JSON for QR encoding — excludes keyData to fit within QR capacity (~4K chars)
    private var exportJSONCompact: String {
        var dict = buildKeystoreDict()
        // Strip keyData from cb-mpc section for QR (too large for QR encoding)
        if var cbmpc = dict["cb-mpc"] as? [String: Any] {
            cbmpc.removeValue(forKey: "keyData")
            dict["cb-mpc"] = cbmpc
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    private var exportDataForFormat: String {
        switch exportFormat {
        case "privateKey":
            if let keyData = UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") {
                return keyData.base64EncodedString()
            }
            return "No key data available"
        case "seedPhrase":
            return "Seed phrase export not available for MPC keys"
        default:
            return exportJSON
        }
    }

    private var exportFormatLabel: String {
        switch exportFormat {
        case "privateKey": return "Private Key"
        case "seedPhrase": return "Seed Phrase"
        default: return "KeyStore V3 JSON"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header -- tap name to edit
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        if isEditingName {
                            HStack {
                                TextField("Key Name", text: $editedName)
                                    .font(.system(.headline, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { saveName() }
                                Button(action: saveName) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                                Button(action: { isEditingName = false }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Text(key.name)
                                .font(.system(.headline, design: .monospaced))
                                .onTapGesture {
                                    editedName = key.name
                                    isEditingName = true
                                }
                        }
                        Text(key.displayKeyType)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    // QR glyph opens QR detail sheet (public key only)
                    Button(action: { activeSheet = .qrShare }) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)

                // Key custody indicator (tappable for co-signer details)
                custodyBadgeView
                    .contentShape(Rectangle())
                    .onTapGesture {
                        activeSheet = .coSigner
                    }

                // Public Key Display -- 3/4 on top, 1/4 on bottom with copy glyph
                VStack(alignment: .leading, spacing: 6) {
                    Text("PUBLIC KEY")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("0x" + publicKeyFirstPart)
                            .font(.system(.caption2, design: .monospaced))
                        HStack(spacing: 4) {
                            Text(publicKeySecondPart)
                                .font(.system(.caption2, design: .monospaced))
                            copyButton("0x" + key.publicKey, id: "pubkey")
                        }
                    }
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.gray.opacity(0.1))
                    .cornerRadius(4)

                    if let path = key.derivationPath {
                        Text(path)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)

                // Metadata
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Curve")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("secp256k1 (\(key.curveCode))")
                            .font(.system(.caption, design: .monospaced))
                    }

                    if let preset = key.derivationPreset {
                        Divider()
                        HStack {
                            Text("Derivation Standard")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(preset)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }

                    if key.keyType == .hdChild, let parentId = key.parentKeyId,
                       let parentKey = keyStore.keys.first(where: { $0.id == parentId }) {
                        Divider()
                        NavigationLink(destination: KeyDetailView(key: parentKey).environmentObject(keyStore)) {
                            HStack {
                                Text("HD Master")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text("0x\(parentKey.shortAddress)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    if let path = key.derivationPath {
                        Divider()
                        HStack {
                            Text("Derivation Path")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text(path)
                                    .font(.system(.caption, design: .monospaced))
                                copyButton(path, id: "path")
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Text("Storage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(key.displayStorageLocation)
                            .font(.system(.caption, design: .monospaced))
                    }

                    Divider()

                    HStack {
                        Text("Created")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(AppDateFormat.string(from: key.createdAt))
                            .font(.system(.caption, design: .monospaced))
                    }

                    if key.isBackedUp {
                        Divider()
                        HStack {
                            Text("Source")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Imported")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                    }

                    if let lastUsed = key.lastUsedAt {
                        Divider()
                        HStack {
                            Text("Last Used")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(AppDateFormat.string(from: lastUsed))
                                .font(.system(.caption, design: .monospaced))
                        }
                    }

                    Divider()

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Filename")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            let fParts = utcFileName.components(separatedBy: "--")
                            if fParts.count >= 3 {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("\(fParts[0])--\(fParts[1])--")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text("\(fParts[2]).json")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .textSelection(.enabled)
                            } else {
                                Text("\(utcFileName).json")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                        copyButton("\(utcFileName).json", id: "filename")
                    }

                    Divider()

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud Path")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            let iParts = utcFileName.components(separatedBy: "--")
                            if iParts.count >= 3 {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("iCloud/Key-MGMT-CB-MPC/")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text("\(iParts[0])--\(iParts[1])--")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text("\(iParts[2]).json")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .textSelection(.enabled)
                            } else {
                                Text("iCloud/Key-MGMT-CB-MPC/\(utcFileName).json")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                        copyButton("iCloud/Key-MGMT-CB-MPC/\(utcFileName).json", id: "icloudpath")
                    }
                }
                .padding(8)
                .background(.gray.opacity(0.1))
                .cornerRadius(4)

                Divider()

                // Operations
                VStack(alignment: .leading, spacing: 8) {
                    if hasKeyData {
                        HStack(spacing: 6) {
                            Button(action: { activeSheet = .signing }) {
                                Label("Sign", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button(action: { activeSheet = .signTx }) {
                                Label("Sign Tx", systemImage: "arrow.right.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    } else {
                        Text("No key data -- regenerate this key to enable signing")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.orange)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.1))
                            .cornerRadius(4)
                    }

                    HStack(spacing: 6) {
                        Button(action: { activeSheet = .verify }) {
                            Text("Verify")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                        .disabled(key.signingRecords.isEmpty)

                        if key.keyType == .hdMaster {
                            Button(action: { activeSheet = .derive }) {
                                Text("Derive")
                                    .font(.system(size: 9, design: .monospaced))
                            }
                            .controlSize(.mini)
                            .buttonStyle(.bordered)
                        }

                        Button(action: { activeSheet = .export }) {
                            Text("Export")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.bottom, 12)

                Divider()

                // Signing History
                VStack(alignment: .leading, spacing: 6) {
                    Text("SIGNING HISTORY")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))

                    if key.signingRecords.isEmpty {
                        Text("No signing history")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(key.signingRecords.prefix(10)) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(AppDateFormat.string(from: record.timestamp))
                                        .font(.system(size: 9, design: .monospaced))
                                    Text(key.displayKeyType)
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    // Delete glyph right after key type
                                    Button(action: {
                                        keyStore.deleteSigningRecord(record.id, from: key.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 9))
                                            .foregroundColor(.red.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    Spacer()
                                    if record.verified {
                                        Label("VERIFIED", systemImage: "checkmark.circle.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(.green)
                                    }
                                }

                                // Full SHA-256 hash - no truncation
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("SHA-256")
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Text(record.messageHash)
                                            .font(.system(size: 7, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 4)
                                    copyButton(record.messageHash, id: "hash-\(record.id)")
                                }

                                // Full signature - no truncation
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("SIGNATURE")
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Text(record.signature)
                                            .font(.system(size: 7, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 4)
                                    copyButton(record.signature, id: "sig-\(record.id)")
                                }

                                // Transport details
                                if let transport = record.transportInfo {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.branch")
                                            .font(.system(size: 7))
                                            .foregroundColor(.blue.opacity(0.7))
                                        Text(transport)
                                            .font(.system(size: 7, design: .monospaced))
                                            .foregroundColor(.blue.opacity(0.7))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(6)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)
                            .onTapGesture {
                                shareSigningRecord(record)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(12)
        }
        .navigationTitle("Key Details")
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .signing:
                SignMessageSheetView(key: key)
                    .environmentObject(keyStore)
            case .signTx:
                SignTransactionSheetView(key: key)
            case .verify:
                VerifySignatureSheetView(key: key)
            case .qrShare:
                qrDetailSheet
                    .presentationDetents([.large])
            case .derive:
                DeriveChildSheetView(masterKey: key) { newKeyId in
                    navigateToDerivedKeyId = newKeyId
                }
                .environmentObject(keyStore)
            case .export:
                ExportKeySheetView(key: key, exportJSON: exportJSON, utcFileName: utcFileName, exportFormatLabel: exportFormatLabel, exportDataForFormat: exportDataForFormat)
                    .environmentObject(keyStore)
                    .presentationDetents([.medium, .large])
            case .coSigner:
                CoSignerDetailSheetView(key: key)
                    .environmentObject(keyStore)
                    .presentationDetents([.medium, .large])
            }
        }
        .navigationDestination(item: $navigateToDerivedKeyId) { keyId in
            if let derivedKey = keyStore.keys.first(where: { $0.id == keyId }) {
                KeyDetailView(key: derivedKey)
                    .environmentObject(keyStore)
            }
        }
    }

    // MARK: - Custody Badge

    @ViewBuilder
    private var custodyBadgeView: some View {
        let origin = TransportOrigin.load(for: key.id)
        let coSigner = TransportOrigin.coSignerRef(for: key.id)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: origin.shieldIcon)
                    .font(.system(size: 10))
                    .foregroundColor(origin.badgeColor)
                Text(origin.badgeText)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(origin.badgeColor)
                Spacer()
                Text(origin.shareDescription)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if origin == .server, let serverURL = coSigner {
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("Co-signer: \(serverURL)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else if origin == .peer, let deviceIdStr = coSigner,
                      let deviceUUID = UUID(uuidString: deviceIdStr) {
                let peerDevice = PairingManager.shared.pairedDevices.first(where: { $0.id == deviceUUID })
                HStack(spacing: 4) {
                    Image(systemName: "iphone")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    if let device = peerDevice {
                        Text("Co-signer: \(device.name) (\(device.deviceModel))")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Co-signer: Paired device \(deviceIdStr.prefix(8))...")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(8)
        .background(origin.badgeColor.opacity(0.08))
        .cornerRadius(4)
    }

    // MARK: - Copy Button (turns blue on tap)

    @ViewBuilder
    private func copyButton(_ text: String, id: String) -> some View {
        Button(action: {
            #if os(iOS)
            UIPasteboard.general.string = text
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedId = id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if copiedId == id {
                    withAnimation { copiedId = nil }
                }
            }
        }) {
            Image(systemName: copiedId == id ? "checkmark.circle.fill" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundColor(copiedId == id ? .blue : .secondary)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Share Signing Record

    private func shareSigningRecord(_ record: SigningRecord) {
        let text = """
        CB-MPC Signing Record
        =====================

        Date:       \(AppDateFormat.string(from: record.timestamp))
        Key:        \(key.name)
        Type:       \(key.displayKeyType)
        Public Key: 0x\(key.publicKey)
        Verified:   \(record.verified ? "Yes" : "No")

        SHA-256 Hash:
        \(record.messageHash)

        Signature:
        \(record.signature)
        """

        #if os(iOS)
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
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
    }

    // MARK: - Save Name

    private func saveName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isEditingName = false
            return
        }
        keyStore.updateKeyName(key.id, newName: trimmed)
        isEditingName = false
    }


    // MARK: - QR Code Generator

    private func generateQRCode(from string: String, correctionLevel: String = "M") -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = correctionLevel

        if let outputImage = filter.outputImage {
            let scale = 200.0 / outputImage.extent.size.width
            let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            if let cgImage = context.createCGImage(transformed, from: transformed.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return UIImage(systemName: "qrcode") ?? UIImage()
    }

    private func generateQRCode(from data: Data) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "L"

        if let outputImage = filter.outputImage {
            let scale = 200.0 / outputImage.extent.size.width
            let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            if let cgImage = context.createCGImage(transformed, from: transformed.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return UIImage(systemName: "qrcode") ?? UIImage()
    }

    // MARK: - QR Detail Sheet (plain 0x public key -- NOT JSON)

    private var qrDetailSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Large QR code encoding 0x<publicKey>
                    HStack {
                        Spacer()
                        Button(action: {
                            #if os(iOS)
                            UIPasteboard.general.string = publicKeyHex
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            #endif
                            copiedId = "qr-tap"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedId == "qr-tap" { copiedId = nil }
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(uiImage: generateQRCode(from: publicKeyHex))
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 200, height: 200)
                                    .padding(12)
                                    .background(.white)
                                    .cornerRadius(8)
                                if copiedId == "qr-tap" {
                                    Text("Copied to clipboard")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.blue)
                                } else {
                                    Text("Tap to copy")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }

                    // Wallet details
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(key.name)
                                .font(.system(.caption, design: .monospaced))
                        }

                        Divider()

                        HStack {
                            Text("Type")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(key.displayKeyType)
                                .font(.system(.caption, design: .monospaced))
                        }

                        if key.keyType == .hdChild, let parentId = key.parentKeyId,
                           let parentKey = keyStore.keys.first(where: { $0.id == parentId }) {
                            Divider()
                            HStack {
                                Text("HD Master")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(parentKey.name)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }

                        if let path = key.derivationPath {
                            Divider()
                            HStack {
                                Text("Derivation Path")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(path)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }

                        Divider()

                        HStack {
                            Text("Created")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(AppDateFormat.string(from: key.createdAt))
                                .font(.system(.caption, design: .monospaced))
                        }

                        if key.isBackedUp {
                            Divider()
                            HStack {
                                Text("Source")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Imported")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.blue)
                            }
                        }

                        Divider()

                        HStack {
                            Text("Storage")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(key.displayStorageLocation)
                                .font(.system(.caption, design: .monospaced))
                        }

                        Divider()

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Filename")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(utcFileName).json")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            copyButton("\(utcFileName).json", id: "qr-filename")
                        }

                        Divider()

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("iCloud Path")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("iCloud/Key-MGMT-CB-MPC/\(utcFileName).json")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            copyButton("iCloud/Key-MGMT-CB-MPC/\(utcFileName).json", id: "qr-icloudpath")
                        }
                    }
                    .padding(8)
                    .background(.gray.opacity(0.1))
                    .cornerRadius(4)

                    // Plain 0x public key text
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PUBLIC KEY")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)

                        HStack(alignment: .top, spacing: 4) {
                            Text(publicKeyHex)
                                .font(.system(size: 9, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            copyButton(publicKeyHex, id: "qr-pubkey")
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(4)
                    }

                    // Share button
                    ShareLink(item: publicKeyHex) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
            .navigationTitle("Share Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { activeSheet = nil }
                }
            }
        }
    }


}

// MARK: - Derive Child Sheet

struct DeriveChildSheetView: View {
    let masterKey: ManagedKey
    var onDerived: ((UUID) -> Void)?
    @EnvironmentObject var keyStore: KeyStore
    @Environment(\.dismiss) var dismiss

    @State private var derivationPath = "m/44'/60'/0'/0/0"
    @State private var childName = ""
    @State private var isDeriving = false
    @State private var deriveError: String?
    @State private var selectedPreset: String = "metamask"
    @State private var copiedChildId: String?
    @AppStorage("hdChildNamingUseSelf") private var hdChildNamingUseSelf = false

    /// Existing child keys derived from this master
    private var existingChildren: [ManagedKey] {
        keyStore.keys.filter { $0.parentKeyId == masterKey.id && $0.keyType == .hdChild }
    }

    /// Existing derivation paths for this master
    private var existingPaths: Set<String> {
        Set(existingChildren.compactMap { $0.derivationPath })
    }

    /// Auto-compute next available derivation path based on preset and existing children
    private func nextAvailablePath(for preset: String) -> String {
        switch preset {
        case "metamask":
            // MetaMask: m/44'/60'/0'/0/N -- increment N
            for n in 0...999 {
                let path = "m/44'/60'/0'/0/\(n)"
                if !existingPaths.contains(path) { return path }
            }
            return "m/44'/60'/0'/0/0"
        case "ledger":
            // Ledger: m/44'/60'/N'/0/0 -- increment N
            for n in 0...999 {
                let path = "m/44'/60'/\(n)'/0/0"
                if !existingPaths.contains(path) { return path }
            }
            return "m/44'/60'/0'/0/0"
        default:
            return "m/44'/60'/0'"
        }
    }

    private var accountNumber: String {
        let parts = derivationPath.split(separator: "/")
        if let last = parts.last {
            return String(last).replacingOccurrences(of: "'", with: "")
        }
        return "0"
    }

    private var defaultChildName: String {
        let addr = masterKey.shortAddress
        let dateStr = AppDateFormat.string(from: Date())
        return "\(addr)/\(accountNumber) \(dateStr)"
    }

    private var pathAlreadyExists: Bool {
        existingPaths.contains(derivationPath)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PARENT KEY")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(masterKey.name)
                        .font(.system(.caption, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CHILD NAME")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    TextField(defaultChildName, text: $childName)
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("DERIVATION PATH")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    TextField("m/44'/60'/0'/0/0", text: $derivationPath)
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if pathAlreadyExists {
                        Text("This path is already derived -- choose a different path")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.red)
                    } else if selectedPreset == "metamask" {
                        Text("Increments address index: m/44'/60'/0'/0/N")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    } else if selectedPreset == "ledger" {
                        Text("Increments account: m/44'/60'/N'/0/0")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    } else {
                        Text("Custom derivation path")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    HStack(spacing: 6) {
                        Button("MetaMask") {
                            selectedPreset = "metamask"
                            derivationPath = nextAvailablePath(for: "metamask")
                        }
                        .font(.system(size: 9))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(selectedPreset == "metamask" ? .blue : .gray)

                        Button("Ledger Live") {
                            selectedPreset = "ledger"
                            derivationPath = nextAvailablePath(for: "ledger")
                        }
                        .font(.system(size: 9))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(selectedPreset == "ledger" ? .blue : .gray)

                        Button("Custom") {
                            selectedPreset = "custom"
                            derivationPath = "m/44'/60'/0'"
                        }
                        .font(.system(size: 9))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(selectedPreset == "custom" ? .blue : .gray)
                    }

                    // Show existing derived children
                    if !existingChildren.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DERIVED (\(existingChildren.count))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                            ForEach(existingChildren) { child in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(child.derivationPath ?? "?")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    HStack(alignment: .top, spacing: 4) {
                                        Text("0x\(child.publicKey)")
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(.secondary.opacity(0.7))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 4)
                                        Button(action: {
                                            #if os(iOS)
                                            UIPasteboard.general.string = "0x\(child.publicKey)"
                                            let impact = UIImpactFeedbackGenerator(style: .light)
                                            impact.impactOccurred()
                                            #endif
                                            copiedChildId = child.id.uuidString
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                if copiedChildId == child.id.uuidString { copiedChildId = nil }
                                            }
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 8))
                                                .foregroundColor(copiedChildId == child.id.uuidString ? .blue : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(.gray.opacity(0.05))
                        .cornerRadius(4)
                    }
                }

                if let err = deriveError {
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                }

                Spacer()

                Button(action: deriveChild) {
                    if isDeriving {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Deriving...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Derive Child Key", systemImage: "arrow.triangle.branch")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDeriving || pathAlreadyExists)
            }
            .padding(16)
            .navigationTitle("Derive Child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Auto-suggest next available path on sheet open
                derivationPath = nextAvailablePath(for: selectedPreset)
            }
        }
    }

    private func deriveChild() {
        isDeriving = true
        deriveError = nil

        let name = childName.isEmpty ? defaultChildName : childName

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let newKey = try keyStore.deriveChildKey(from: masterKey, path: derivationPath, name: name)
                DispatchQueue.main.async {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    isDeriving = false
                    dismiss()
                    // Navigate to the new key's detail view
                    onDerived?(newKey.id)
                }
            } catch {
                DispatchQueue.main.async {
                    deriveError = "Derivation failed: \(error.localizedDescription)"
                    isDeriving = false
                }
            }
        }
    }
}

// MARK: - Co-Signer Detail Sheet

struct CoSignerDetailSheetView: View {
    let key: ManagedKey
    @EnvironmentObject var keyStore: KeyStore
    @Environment(\.dismiss) var dismiss

    private var origin: TransportOrigin {
        TransportOrigin.load(for: key.id)
    }

    private var coSignerRef: String? {
        TransportOrigin.coSignerRef(for: key.id)
    }

    private var coSignedKeys: [ManagedKey] {
        guard let ref = coSignerRef else { return [] }
        return TransportOrigin.keysWithCoSigner(ref, in: keyStore.keys)
    }

    private var signingHistory: [(key: ManagedKey, record: SigningRecord)] {
        coSignedKeys.flatMap { k in
            k.signingRecords.map { (key: k, record: $0) }
        }
        .sorted { $0.record.timestamp > $1.record.timestamp }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("CO-SIGNER")) {
                    HStack(spacing: 6) {
                        Image(systemName: origin.shieldIcon)
                            .font(.system(size: 14))
                            .foregroundColor(origin.badgeColor)
                        Text(origin.badgeText)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(origin.badgeColor)
                    }

                    Text(origin.shareDescription)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                switch origin {
                case .server:
                    serverDetailSection
                case .peer:
                    peerDetailSection
                case .local:
                    Section(header: Text("LOCAL KEY")) {
                        Text("Both key shares are stored on this device. No external co-signer.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        SecurityRow(title: "Security",
                                    description: "Both shares protected by iOS data protection (AES-256 at rest). Consider exporting one share to a server or paired device for improved security.")
                    }
                }

                if coSignedKeys.count > 1 {
                    Section(header: Text("ALL KEYS WITH THIS CO-SIGNER")) {
                        ForEach(coSignedKeys) { k in
                            HStack(spacing: 8) {
                                Image(systemName: k.keyType == .hdMaster ? "key.radiowaves.forward" : "key.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(k.name)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .lineLimit(1)
                                    Text(k.shortAddress)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(k.displayKeyType)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if !signingHistory.isEmpty {
                    Section(header: Text("SIGNING HISTORY")) {
                        ForEach(signingHistory.prefix(5), id: \.record.id) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.key.name)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(formatDate(entry.record.timestamp))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Text(entry.record.messageHash.prefix(32) + "...")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary)
                                if let transport = entry.record.transportInfo {
                                    Text(transport)
                                        .font(.system(size: 7, design: .monospaced))
                                        .foregroundColor(.blue.opacity(0.7))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Co-Signer Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var serverDetailSection: some View {
        if let serverURL = coSignerRef {
            let server = PairingManager.shared.servers.first(where: { $0.url == serverURL })
            Section(header: Text("SERVER")) {
                InfoRow(label: "Name", value: server?.name ?? "MPC Server")
                InfoRow(label: "URL", value: serverURL)
                if let server = server {
                    InfoRow(label: "Registered", value: formatAbsoluteDate(server.registeredAt))
                    if let devId = server.serverDeviceId {
                        InfoRow(label: "Device ID", value: devId)
                    }
                    InfoRow(label: "Status", value: server.isOnline ? "Online" : "Offline")
                    InfoRow(label: "Auth", value: server.isRegistered ? "Authenticated" : "Not registered")
                }
            }
        }
    }

    @ViewBuilder
    private var peerDetailSection: some View {
        if let deviceIdStr = coSignerRef,
           let deviceUUID = UUID(uuidString: deviceIdStr) {
            let device = PairingManager.shared.pairedDevices.first(where: { $0.id == deviceUUID })
            Section(header: Text("PAIRED DEVICE")) {
                if let device = device {
                    InfoRow(label: "Name", value: device.name)
                    InfoRow(label: "Model", value: device.deviceModel)
                    // Fingerprint from public key
                    let fingerprint = SHA256.hash(data: device.publicKey)
                        .prefix(8)
                        .map { String(format: "%02X", $0) }
                        .joined(separator: ":")
                    InfoRow(label: "Fingerprint", value: fingerprint)
                    InfoRow(label: "Paired", value: formatAbsoluteDate(device.pairedAt))
                    let connState = PairingManager.shared.connectionState(for: device.id)
                    InfoRow(label: "Connection", value: connectionLabel(connState))
                } else {
                    InfoRow(label: "Device ID", value: deviceIdStr)
                    Text("Device no longer paired")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private func connectionLabel(_ state: PeerConnectionManager.ConnectionState) -> String {
        switch state {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .searching: return "Searching..."
        case .disconnected: return "Disconnected"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func formatAbsoluteDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let mockKey = ManagedKey(
        id: UUID(),
        name: "My Ethereum Wallet",
        publicKey: "02a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6",
        keyType: .simple,
        curveCode: 714,
        derivationPath: nil,
        parentKeyId: nil,
        storageLocation: .secureEnclave,
        createdAt: Date(),
        lastUsedAt: Date(),
        isBackedUp: true,
        signingRecords: []
    )

    return NavigationStack {
        KeyDetailView(key: mockKey)
            .environmentObject(KeyStore())
    }
}
