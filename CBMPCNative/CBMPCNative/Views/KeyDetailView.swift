import SwiftUI
import CoreImage.CIFilterBuiltins
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct KeyDetailView: View {
    let key: ManagedKey
    @EnvironmentObject var keyStore: KeyStore
    @State private var showSigningSheet = false
    @State private var showSignTxSheet = false
    @State private var showVerifySheet = false
    @State private var showExportSheet = false
    @State private var showQRShareSheet = false
    @State private var showDeriveSheet = false
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var copiedId: String?
    @AppStorage("exportFormat") private var exportFormat = "keystoreJSON"

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
        var dict: [String: Any] = [
            "name": key.name,
            "publicKey": key.publicKey,
            "keyType": key.keyType.rawValue,
            "curveCode": Int(key.curveCode),
            "createdAt": ISO8601DateFormatter().string(from: key.createdAt)
        ]
        if let path = key.derivationPath {
            dict["derivationPath"] = path
        }
        if exportFormat == "keystoreJSON" {
            if let keyData = UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") {
                dict["keyData"] = keyData.base64EncodedString()
            }
        }
        return dict
    }

    private var exportJSON: String {
        let dict = buildKeystoreDict()
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    /// Compact JSON for QR encoding (no pretty printing to fit in QR capacity)
    private var exportJSONCompact: String {
        let dict = buildKeystoreDict()
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
                    Button(action: { showQRShareSheet = true }) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)

                // Public Key Display -- 3/4 on top, 1/4 on bottom with copy glyph
                VStack(alignment: .leading, spacing: 6) {
                    Text("PUBLIC KEY")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(publicKeyFirstPart)
                            .font(.system(.caption2, design: .monospaced))
                        HStack(spacing: 4) {
                            Text(publicKeySecondPart)
                                .font(.system(.caption2, design: .monospaced))
                            copyButton(key.publicKey, id: "pubkey")
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
                }
                .padding(8)
                .background(.gray.opacity(0.1))
                .cornerRadius(4)

                Divider()

                // Operations
                VStack(alignment: .leading, spacing: 8) {
                    if hasKeyData {
                        HStack(spacing: 6) {
                            Button(action: { showSigningSheet = true }) {
                                Label("Sign", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button(action: { showSignTxSheet = true }) {
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
                        Button(action: { showVerifySheet = true }) {
                            Text("Verify")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                        .disabled(key.signingRecords.isEmpty)

                        if key.keyType == .hdMaster {
                            Button(action: { showDeriveSheet = true }) {
                                Text("Derive")
                                    .font(.system(size: 9, design: .monospaced))
                            }
                            .controlSize(.mini)
                            .buttonStyle(.bordered)
                        }

                        Button(action: { showExportSheet = true }) {
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
                            }
                            .padding(6)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                }

                Spacer()
            }
            .padding(12)
        }
        .navigationTitle("Key Details")
        .sheet(isPresented: $showSigningSheet) {
            SignMessageSheetView(key: key)
                .environmentObject(keyStore)
        }
        .sheet(isPresented: $showSignTxSheet) {
            SignTransactionSheetView(key: key)
        }
        .sheet(isPresented: $showVerifySheet) {
            VerifySignatureSheetView(key: key)
        }
        .sheet(isPresented: $showQRShareSheet) {
            qrDetailSheet
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showDeriveSheet) {
            DeriveChildSheetView(masterKey: key)
                .environmentObject(keyStore)
        }
        .sheet(isPresented: $showExportSheet) {
            exportSheetContent
                .presentationDetents([.medium, .large])
        }
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

                        if let path = key.derivationPath {
                            Divider()
                            HStack {
                                Text("Derivation")
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
                                .font(.system(size: 8, design: .monospaced))
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
                    Button("Close") { showQRShareSheet = false }
                }
            }
        }
    }

    // MARK: - Export Sheet (QR encodes keystore JSON)

    private var exportSheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                        Text("Private keys and seed phrases should only exist in Secure Enclave, encrypted iCloud, or encrypted on a USB-C device.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    .padding(10)
                    .background(.orange.opacity(0.1))
                    .cornerRadius(6)

                    // QR code of export/keystore JSON data (compact, low correction for capacity)
                    HStack {
                        Spacer()
                        Image(uiImage: generateQRCode(from: exportJSONCompact, correctionLevel: "L"))
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 160, height: 160)
                            .padding(8)
                            .background(.white)
                            .cornerRadius(8)
                        Spacer()
                    }

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

                    Button(action: { showExportSheet = false }) {
                        Label("Done", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
            .navigationTitle("Export Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showExportSheet = false }
                }
            }
        }
    }

    private var exportFormatLabel: String {
        switch exportFormat {
        case "privateKey": return "Private Key"
        case "seedPhrase": return "Seed Phrase"
        default: return "JSON"
        }
    }
}

// MARK: - Derive Child Sheet

struct DeriveChildSheetView: View {
    let masterKey: ManagedKey
    @EnvironmentObject var keyStore: KeyStore
    @Environment(\.dismiss) var dismiss

    @State private var derivationPath = "m/44'/60'/0'/0/0"
    @State private var childName = ""
    @State private var isDeriving = false
    @State private var deriveError: String?
    @AppStorage("hdChildNamingUseSelf") private var hdChildNamingUseSelf = false

    private var accountFromPath: String {
        let parts = derivationPath.split(separator: "/")
        if parts.count >= 5 {
            let addressIndex = String(parts[4]).replacingOccurrences(of: "'", with: "")
            return addressIndex
        } else if parts.count >= 3 {
            let account = String(parts[2]).replacingOccurrences(of: "'", with: "")
            return account
        }
        return "0"
    }

    private var defaultChildName: String {
        let addr = masterKey.shortAddress
        let dateStr = AppDateFormat.string(from: Date())
        return "\(addr)/\(derivationPath) \(dateStr)"
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

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Button("MetaMask") { derivationPath = "m/44'/60'/0'/0/0" }
                                .font(.system(size: 9))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            Button("Ledger Live") { derivationPath = "m/44'/60'/0'/0/0" }
                                .font(.system(size: 9))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            Button("Custom") { derivationPath = "m/44'/60'/0'" }
                                .font(.system(size: 9))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                        }

                        Text("MetaMask: increments address index (m/44'/60'/0'/0/N)\nLedger Live: increments account (m/44'/60'/N'/0/0)")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
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
                .disabled(isDeriving)
            }
            .padding(16)
            .navigationTitle("Derive Child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func deriveChild() {
        isDeriving = true
        deriveError = nil

        let name = childName.isEmpty ? defaultChildName : childName

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let _ = try keyStore.deriveChildKey(from: masterKey, path: derivationPath, name: name)
                DispatchQueue.main.async {
                    isDeriving = false
                    dismiss()
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
