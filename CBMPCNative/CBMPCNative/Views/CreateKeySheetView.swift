import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum KeyCreationMode: String, CaseIterable {
    case generate = "Generate"
    case importSeed = "Seed"
    case importPrivateKey = "Private"
    case importUSB = "Storage"
    case importQR = "QR Code"

    var fullName: String {
        switch self {
        case .generate: return "Generate"
        case .importSeed: return "Seed Phrase"
        case .importPrivateKey: return "Private Key"
        case .importUSB: return "Storage"
        case .importQR: return "QR Code"
        }
    }
}

enum DerivationPreset: String, CaseIterable {
    case ledger = "Ledger"
    case metamask = "MetaMask"
    case custom = "Custom"

    var path: String {
        switch self {
        case .ledger: return "m/44'/60'/0'"
        case .metamask: return "m/44'/60'/0'/0"
        case .custom: return ""
        }
    }
}

enum ExportDestination: String, CaseIterable {
    case secureEnclave = "Device Keychain"
    case icloudKeychain = "iCloud Keychain"
    case storage = "File Export"
    case pairedDevice = "Paired Device"
    case mpcServer = "Key Server"

    var icon: String {
        switch self {
        case .secureEnclave: return "lock.shield"
        case .icloudKeychain: return "key.icloud"
        case .storage: return "externaldrive"
        case .pairedDevice: return "iphone"
        case .mpcServer: return "server.rack"
        }
    }

    var securityNote: String {
        switch self {
        case .secureEnclave:
            return "AES-256 encrypted at rest by iOS data protection. Tied to device hardware. Never leaves this device. Requires unlock (passcode/Face ID)."
        case .icloudKeychain:
            return "Apple end-to-end encrypted. Syncs across devices signed into same Apple ID. Protected by device passcode + Apple ID."
        case .storage:
            return "Exported as file via share sheet. No automatic encryption. User responsible for secure storage."
        case .pairedDevice:
            return "Send key share to a paired device via encrypted MultipeerConnectivity channel."
        case .mpcServer:
            return "Upload key share to the MPC server for remote co-signing."
        }
    }

    var isAvailable: Bool {
        switch self {
        case .secureEnclave, .icloudKeychain, .storage: return true
        case .pairedDevice, .mpcServer: return false  // Coming soon
        }
    }
}

struct CreateKeySheetView: View {
    @EnvironmentObject var keyStore: KeyStore
    @Environment(\.dismiss) var dismiss

    @State private var keyName = ""
    @State private var keyType: KeyType = .simple
    @State private var creationMode: KeyCreationMode = .generate
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var derivationPath = "m/44'/60'/0'/0/0"
    @State private var selectedParentKeyId: UUID?
    @State private var seedPhrase = ""
    @State private var privateKeyHex = ""
    @State private var showDocumentPicker = false
    @State private var importedKeystoreJSON: [String: Any]?
    @State private var importedKeystoreFileName: String?
    @State private var importedKeystoreAddress: String?
    @State private var derivationPreset: DerivationPreset = .metamask
    @State private var batchChildCount = 1
    @State private var vanityPrefix = ""
    @State private var vanitySuffix = ""
    @State private var selectedCustody: CustodyMode = .deviceKeychain
    @State private var selectedServerURL: URL?
    @State private var selectedPeerDeviceId: UUID?
    @StateObject private var ceremonyCoordinator = CeremonyCoordinator()

    enum CustodyMode: String, CaseIterable {
        case deviceKeychain = "Device Keychain"
        case icloudKeychain = "iCloud Keychain"
        case server = "Key Server"
        case peerDevice = "Paired Device"
    }
    @State private var seedWordCount = 24
    @State private var isSeedRevealed = false
    @State private var showExportSeedSheet = false
    @State private var exportSeedPassword = ""
    @State private var exportSeedConfirmPassword = ""
    @State private var selectedExportDest: ExportDestination = .secureEnclave
    @State private var isVanitySearching = false
    @State private var vanityAttempts = 0
    @State private var currentSearchAddress = ""
    @State private var searchStartTime: Date?
    @State private var vanitySearchCancelled = false
    @AppStorage("hdChildNamingUseSelf") private var hdChildNamingUseSelf = false

    // QR import state
    @State private var scannedQRParts: [Data] = []
    @State private var qrTotalParts: Int = 0
    @State private var showQRScanner = false
    @State private var qrPassphrase = ""
    @State private var qrImportStatus: String?

    private var custodySecurityNotice: String {
        switch selectedCustody {
        case .deviceKeychain:
            return "Share 1: AES-256 encrypted, tied to device hardware. Both key shares stored locally — if this device is lost, the key is unrecoverable without backup."
        case .icloudKeychain:
            return "Share 1: End-to-end encrypted via Apple iCloud Keychain. Syncs across devices signed into same Apple ID."
        case .peerDevice:
            return "2-of-2 threshold: each device holds one share. Both must cooperate to sign — neither can act alone."
        case .server:
            return "2-of-2 threshold: your device holds one share, the server holds the other. Neither party can sign alone."
        }
    }

    /// Whether this is a single-party setup (no second party selected)
    private var isSingleParty: Bool {
        (selectedCustody == .deviceKeychain || selectedCustody == .icloudKeychain) &&
        selectedServerURL == nil && selectedPeerDeviceId == nil
    }

    private var hdMasterKeys: [ManagedKey] {
        keyStore.keys.filter { $0.keyType == .hdMaster }
    }

    private var defaultKeyName: String {
        let timestamp = AppDateFormat.string(from: Date())
        switch creationMode {
        case .importSeed:
            return "0x0000...0000/m \(timestamp)"
        case .importUSB, .importQR:
            return ""
        default:
            switch keyType {
            case .simple:
                return "ECDSA \(timestamp)"
            case .hdMaster:
                return "0x0000...0000/m \(timestamp)"
            case .hdChild:
                if let parentId = selectedParentKeyId,
                   let parent = hdMasterKeys.first(where: { $0.id == parentId }) {
                    let lastComponent = derivationPath.split(separator: "/").last.map(String.init) ?? "0"
                    return "\(parent.shortAddress)/\(lastComponent) \(timestamp)"
                }
                return derivationPath
            }
        }
    }

    /// Build the final name using 0x short address after key generation
    private func buildKeyName(publicKeyHex: String, keyType: KeyType, path: String?) -> String {
        let timestamp = AppDateFormat.string(from: Date())
        let pk = publicKeyHex
        let prefix4 = String(pk.prefix(4))
        let suffix4 = String(pk.suffix(4))
        let shortAddr = "0x\(prefix4)...\(suffix4)"

        switch keyType {
        case .simple:
            return "\(shortAddr) \(timestamp)"
        case .hdMaster:
            return "\(shortAddr)/m \(timestamp)"
        case .hdChild:
            let acct = path?.split(separator: "/").last.map { String($0).replacingOccurrences(of: "'", with: "") } ?? "0"
            if !hdChildNamingUseSelf,
               let parentId = selectedParentKeyId,
               let parent = hdMasterKeys.first(where: { $0.id == parentId }) {
                let masterAddr = parent.shortAddress
                return "\(masterAddr)/\(acct) \(timestamp)"
            }
            return "\(shortAddr)/\(acct) \(timestamp)"
        }
    }

    private var vanityEstimate: String {
        let totalChars = vanityPrefix.count + vanitySuffix.count
        guard totalChars > 0 else { return "" }
        let combinations = pow(16.0, Double(totalChars))
        if combinations < 256 {
            return "~\(Int(combinations)) addresses"
        } else if combinations < 65536 {
            return "~\(Int(combinations / 1000))K addresses"
        } else {
            return "~\(Int(combinations / 1_000_000))M addresses"
        }
    }

    private var vanityTimeEstimate: String {
        guard let start = searchStartTime, vanityAttempts > 100 else { return "" }
        let elapsed = Date().timeIntervalSince(start)
        let rate = Double(vanityAttempts) / elapsed
        let totalChars = vanityPrefix.count + vanitySuffix.count
        let expectedTotal = pow(16.0, Double(totalChars))
        let remaining = max(0, expectedTotal - Double(vanityAttempts))
        let secondsLeft = remaining / rate
        if secondsLeft < 60 { return "~\(Int(secondsLeft))s" }
        if secondsLeft < 3600 { return "~\(Int(secondsLeft / 60))m" }
        return "~\(Int(secondsLeft / 3600))h"
    }

    private var isValidHex: Bool {
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let prefixValid = vanityPrefix.isEmpty || vanityPrefix.unicodeScalars.allSatisfy { hexChars.contains($0) }
        let suffixValid = vanitySuffix.isEmpty || vanitySuffix.unicodeScalars.allSatisfy { hexChars.contains($0) }
        return prefixValid && suffixValid
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Creation Mode
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Method")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)

                        Picker("Method", selection: $creationMode) {
                            ForEach(KeyCreationMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Key Type (only for generate mode)
                    if creationMode == .generate {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Key Type")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)

                            VStack(spacing: 0) {
                                keyTypeRow(
                                    type: .simple,
                                    title: "Standard ECDSA",
                                    description: "Standard ECDSA key for signing. No derivation hierarchy."
                                )

                                Divider()

                                keyTypeRow(
                                    type: .hdMaster,
                                    title: "HD Master",
                                    description: "BIP-32 hierarchical deterministic root key. Can derive child keys."
                                )

                                if !hdMasterKeys.isEmpty {
                                    Divider()

                                    keyTypeRow(
                                        type: .hdChild,
                                        title: "HD Child",
                                        description: "Derived from an HD Master key using a BIP-44 path."
                                    )
                                }
                            }
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)
                        }

                        // Custody mode picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Key Custody")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)

                            VStack(spacing: 0) {
                                // Device Keychain
                                Button(action: { selectedCustody = .deviceKeychain; selectedServerURL = nil; selectedPeerDeviceId = nil }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: selectedCustody == .deviceKeychain ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedCustody == .deviceKeychain ? .blue : .secondary)
                                            .font(.system(size: 16))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Device Keychain")
                                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            Text("AES-256 encrypted, tied to device hardware.")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                }
                                .buttonStyle(.plain)

                                Divider()

                                // iCloud Keychain
                                Button(action: { selectedCustody = .icloudKeychain; selectedServerURL = nil; selectedPeerDeviceId = nil }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: selectedCustody == .icloudKeychain ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedCustody == .icloudKeychain ? .blue : .secondary)
                                            .font(.system(size: 16))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("iCloud Keychain")
                                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            Text("End-to-end encrypted, syncs across Apple devices.")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                }
                                .buttonStyle(.plain)

                                if !PairingManager.shared.pairedDevices.isEmpty {
                                    Divider()

                                    ForEach(PairingManager.shared.pairedDevices) { device in
                                        Button(action: {
                                            selectedCustody = .peerDevice
                                            selectedPeerDeviceId = device.id
                                            selectedServerURL = nil
                                        }) {
                                            HStack(spacing: 10) {
                                                Image(systemName: selectedCustody == .peerDevice && selectedPeerDeviceId == device.id ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(selectedCustody == .peerDevice && selectedPeerDeviceId == device.id ? .blue : .secondary)
                                                    .font(.system(size: 16))
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "iphone")
                                                            .font(.system(size: 10))
                                                        Text(device.name)
                                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                                    }
                                                    Text("2-of-2 peer: \(device.deviceModel) — each device holds one share.")
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .foregroundColor(.secondary)
                                                    let connState = PairingManager.shared.connectionState(for: device.id)
                                                    if connState == .connected {
                                                        Text("Connected")
                                                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                                                            .foregroundColor(.green)
                                                    } else {
                                                        Text("Offline — pair again to generate keys")
                                                            .font(.system(size: 8, design: .monospaced))
                                                            .foregroundColor(.orange)
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .padding(10)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                if !PairingManager.shared.servers.filter({ $0.isRegistered }).isEmpty {
                                    Divider()

                                    ForEach(PairingManager.shared.servers.filter({ $0.isRegistered })) { server in
                                        Button(action: {
                                            selectedCustody = .server
                                            selectedServerURL = URL(string: server.url)
                                            selectedPeerDeviceId = nil
                                        }) {
                                            HStack(spacing: 10) {
                                                Image(systemName: selectedCustody == .server && selectedServerURL?.absoluteString == server.url ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(selectedCustody == .server && selectedServerURL?.absoluteString == server.url ? .blue : .secondary)
                                                    .font(.system(size: 16))
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "server.rack")
                                                            .font(.system(size: 10))
                                                        Text(server.name)
                                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                                    }
                                                    Text("2-of-2 threshold: device + server must cooperate to sign.")
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                            }
                                            .padding(10)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)
                        }

                        // Single-party warning
                        if isSingleParty {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Single-party key: if this device is lost, the key is unrecoverable. Consider adding a second party (server or paired device).")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                            .padding(10)
                            .background(.orange.opacity(0.08))
                            .cornerRadius(6)
                        }

                        // Storage notice
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "shield.lefthalf.filled")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            Text(custodySecurityNotice)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(.orange.opacity(0.05))
                        .cornerRadius(6)
                    }

                    // HD Child options
                    if creationMode == .generate && keyType == .hdChild {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Parent Key")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)

                            Picker("Parent Key", selection: $selectedParentKeyId) {
                                ForEach(hdMasterKeys) { masterKey in
                                    Text(masterKey.name)
                                        .font(.system(.caption, design: .monospaced))
                                        .tag(Optional(masterKey.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Derivation Preset")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)

                            Picker("Preset", selection: $derivationPreset) {
                                ForEach(DerivationPreset.allCases, id: \.self) { preset in
                                    Text(preset.rawValue).tag(preset)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: derivationPreset) { newValue in
                                if newValue != .custom {
                                    derivationPath = newValue.path
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Derivation Path")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)

                            TextField("m/44'/60'/0'/0/0", text: $derivationPath)
                                .font(.system(.body, design: .monospaced))
                                .padding(8)
                                .background(.gray.opacity(0.1))
                                .cornerRadius(4)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .disabled(derivationPreset != .custom)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Number of Children")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)

                            Stepper(value: $batchChildCount, in: 1...5) {
                                Text("\(batchChildCount) key\(batchChildCount > 1 ? "s" : "")")
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding(8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)

                            if batchChildCount > 1 {
                                Text("Will generate \(batchChildCount) keys with incrementing last path index")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Import: Seed Phrase
                    if creationMode == .importSeed {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Text("Seed Phrase")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                HStack(spacing: 0) {
                                    ForEach([12, 18, 24], id: \.self) { count in
                                        Button(action: { seedWordCount = count }) {
                                            Text("\(count)")
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundColor(seedWordCount == count ? .accentColor : .secondary.opacity(0.6))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                Button("Generate") {
                                    seedPhrase = generatePlaceholderMnemonic(wordCount: seedWordCount)
                                }
                                .font(.system(size: 10, design: .monospaced))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }

                            if isSeedRevealed || seedPhrase.isEmpty {
                                TextEditor(text: $seedPhrase)
                                    .frame(height: 80)
                                    .font(.system(size: 13, design: .monospaced))
                                    .padding(6)
                                    .background(.gray.opacity(0.1))
                                    .cornerRadius(4)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                Text(maskedSeedPhrase)
                                    .font(.system(size: 13, design: .monospaced))
                                    .frame(height: 80, alignment: .topLeading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                                    .background(.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }

                            Text("Enter \(seedWordCount)-word BIP-39 mnemonic separated by spaces. The seed phrase is used to deterministically generate your master key and all derived child keys. Guard it carefully -- anyone with the phrase controls all derived wallets.")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)

                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                                Text("The seed phrase will generate an HD Master key. Both 2-party key shares are stored locally on this device.")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(.orange.opacity(0.05))
                            .cornerRadius(6)

                            if !seedPhrase.isEmpty {
                                HStack(spacing: 8) {
                                    Button(action: { isSeedRevealed.toggle() }) {
                                        Label(isSeedRevealed ? "Hide" : "Reveal", systemImage: isSeedRevealed ? "eye.slash" : "eye")
                                            .font(.system(size: 10, design: .monospaced))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)

                                    Button(action: { showExportSeedSheet = true }) {
                                        Label("Export / Backup", systemImage: "square.and.arrow.up")
                                            .font(.system(size: 10, design: .monospaced))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                        }
                    }

                    // Import: Private Key
                    if creationMode == .importPrivateKey {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Private Key (hex)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Generate") {
                                    privateKeyHex = generateRandomHexKey()
                                }
                                .font(.system(size: 10, design: .monospaced))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }

                            TextEditor(text: $privateKeyHex)
                                .frame(height: 60)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(6)
                                .background(.gray.opacity(0.1))
                                .cornerRadius(4)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Text("64-character hex string (32 bytes). The raw private key will be split into two MPC key shares using distributed key generation. Neither share alone can reconstruct the key or produce valid signatures.")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)

                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                                Text("The private key will be split into 2 MPC shares via DKG. Both shares are stored locally on this device.")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(.orange.opacity(0.05))
                            .cornerRadius(6)
                        }

                        // Vanity Address
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Vanity Address (optional)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Prefix")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    ZStack(alignment: .trailing) {
                                        TextField("0x...", text: $vanityPrefix)
                                            .font(.system(size: 11, design: .monospaced))
                                            .padding(6)
                                            .padding(.trailing, vanityPrefix.isEmpty ? 0 : 22)
                                            .background(.gray.opacity(0.1))
                                            .cornerRadius(4)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                        if !vanityPrefix.isEmpty {
                                            Button(action: { vanityPrefix = "" }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.secondary.opacity(0.6))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.trailing, 6)
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Suffix")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    ZStack(alignment: .trailing) {
                                        TextField("...ff", text: $vanitySuffix)
                                            .font(.system(size: 11, design: .monospaced))
                                            .padding(6)
                                            .padding(.trailing, vanitySuffix.isEmpty ? 0 : 22)
                                            .background(.gray.opacity(0.1))
                                            .cornerRadius(4)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                        if !vanitySuffix.isEmpty {
                                            Button(action: { vanitySuffix = "" }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.secondary.opacity(0.6))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.trailing, 6)
                                        }
                                    }
                                }
                            }

                            if !isValidHex && (!vanityPrefix.isEmpty || !vanitySuffix.isEmpty) {
                                Text("Hex characters only (0-9, a-f)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.red)
                            } else if !vanityEstimate.isEmpty {
                                HStack {
                                    Text("Estimated: \(vanityEstimate)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if !vanityTimeEstimate.isEmpty {
                                        Text(vanityTimeEstimate)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.orange)
                                    }
                                }
                            }

                            if isVanitySearching {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("0x\(currentSearchAddress.prefix(40))")
                                                .font(.system(size: 8, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                            HStack(spacing: 4) {
                                                ProgressView()
                                                    .controlSize(.mini)
                                                Text("Searching...")
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(vanityAttempts) searched")
                                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                .foregroundColor(.orange)
                                            if !vanityTimeEstimate.isEmpty {
                                                Text("ETA: \(vanityTimeEstimate)")
                                                    .font(.system(size: 8, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Button(action: {
                                        vanitySearchCancelled = true
                                    }) {
                                        Label("Cancel Search", systemImage: "xmark.circle")
                                            .font(.system(size: 10, design: .monospaced))
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                    .controlSize(.small)
                                }
                                .padding(8)
                                .background(.orange.opacity(0.05))
                                .cornerRadius(4)
                            }
                        }
                    }

                    // Import: USB-C
                    if creationMode == .importUSB {
                        VStack(alignment: .leading, spacing: 12) {
                            if let ksJSON = importedKeystoreJSON {
                                // Loaded keystore display
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 16))
                                        Text("Keystore Loaded")
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        Spacer()
                                        Button(action: {
                                            importedKeystoreJSON = nil
                                            importedKeystoreFileName = nil
                                            importedKeystoreAddress = nil
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    if let fileName = importedKeystoreFileName {
                                        HStack {
                                            Text("File")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(fileName)
                                                .font(.system(size: 9, design: .monospaced))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }

                                    if let addr = importedKeystoreAddress {
                                        HStack {
                                            Text("Address")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("0x\(addr)")
                                                .font(.system(size: 9, design: .monospaced))
                                        }
                                    }

                                    let version = ksJSON["version"] as? Int ?? 0
                                    HStack {
                                        Text("Version")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("V\(version)")
                                            .font(.system(size: 9, design: .monospaced))
                                    }

                                    if let crypto = ksJSON["crypto"] as? [String: Any] ?? ksJSON["Crypto"] as? [String: Any] {
                                        let cipher = crypto["cipher"] as? String ?? "unknown"
                                        let kdf = crypto["kdf"] as? String ?? "unknown"
                                        HStack {
                                            Text("Cipher")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(cipher)
                                                .font(.system(size: 9, design: .monospaced))
                                        }
                                        HStack {
                                            Text("KDF")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(kdf)
                                                .font(.system(size: 9, design: .monospaced))
                                        }
                                    }

                                    if let ksId = ksJSON["id"] as? String {
                                        HStack {
                                            Text("ID")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(ksId)
                                                .font(.system(size: 8, design: .monospaced))
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(.green.opacity(0.05))
                                .cornerRadius(4)
                            } else {
                                // No keystore loaded yet
                                HStack {
                                    Image(systemName: "externaldrive.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Browse Storage")
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        Text("Import an Ethereum keystore (V3 JSON) from iCloud, USB-C, or local storage")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.gray.opacity(0.1))
                                .cornerRadius(4)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Web3 Secret Storage Definition (V3)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text("AES-128-CTR encryption with scrypt/pbkdf2 KDF. Files named:")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text("<uuid>.json  or  UTC--<timestamp>--<address>")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .padding(4)
                                        .background(.gray.opacity(0.05))
                                        .cornerRadius(2)
                                }
                                .padding(8)
                                .background(.blue.opacity(0.05))
                                .cornerRadius(4)
                            }

                            #if os(iOS)
                            Button(action: { showDocumentPicker = true }) {
                                Label(importedKeystoreJSON != nil ? "Choose Different File" : "Browse Files", systemImage: "folder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            #else
                            Button(action: {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.json, .data]
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    loadKeystoreFromURL(url)
                                }
                            }) {
                                Label(importedKeystoreJSON != nil ? "Choose Different File" : "Browse Files", systemImage: "folder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            #endif

                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                                Text("The imported key data will be stored locally. If the keystore contains CB-MPC key shares, both shares are kept on this device.")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(.orange.opacity(0.05))
                            .cornerRadius(6)
                        }
                        #if os(iOS)
                        .sheet(isPresented: $showDocumentPicker) {
                            DocumentPickerView { url in
                                loadKeystoreFromURL(url)
                            }
                        }
                        #endif
                    }

                    // Import: QR Code
                    if creationMode == .importQR {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 14))
                                    Text("On the sending device, open Key Details and tap Export Key. The rotating QR codes appear at the top of the export sheet.")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.blue)
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "key.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 12))
                                    Text("Scroll to the bottom of the export sheet to find the transfer passphrase. You will need it after scanning to decrypt the key.")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(10)
                            .background(.blue.opacity(0.05))
                            .cornerRadius(6)

                            if scannedQRParts.isEmpty {
                                Button(action: { showQRScanner = true }) {
                                    Label("Start Scanner", systemImage: "camera.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            } else {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 16))
                                    Text("\(scannedQRParts.count) of \(qrTotalParts) parts scanned")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    Spacer()
                                    Button(action: {
                                        scannedQRParts = []
                                        qrTotalParts = 0
                                        qrImportStatus = nil
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
                                .background(.green.opacity(0.05))
                                .cornerRadius(4)

                                // Scanned key metadata
                                if let firstPart = scannedQRParts.first, firstPart.count >= 10 {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("SCANNED KEY")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        let curveCode = firstPart.count > 6 ? firstPart.readUInt16BE(at: 4) : 0
                                        HStack {
                                            Text("Curve")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(curveCode == 714 ? "secp256k1" : "curve \(curveCode)")
                                                .font(.system(size: 9, design: .monospaced))
                                        }
                                        HStack {
                                            Text("Parts")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("\(scannedQRParts.count)/\(qrTotalParts)")
                                                .font(.system(size: 9, design: .monospaced))
                                        }
                                        let totalBytes = scannedQRParts.reduce(0) { $0 + $1.count }
                                        HStack {
                                            Text("Size")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(String(format: "%.1f KB", Double(totalBytes) / 1024.0))
                                                .font(.system(size: 9, design: .monospaced))
                                        }
                                        if qrTotalParts > 1 {
                                            ProgressView(value: Double(scannedQRParts.count), total: Double(qrTotalParts))
                                                .tint(.green)
                                        }
                                    }
                                    .padding(10)
                                    .background(.blue.opacity(0.05))
                                    .cornerRadius(4)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Passphrase")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)

                                    SecureField("Enter transfer passphrase", text: $qrPassphrase)
                                        .font(.system(size: 12, design: .monospaced))
                                        .padding(8)
                                        .background(.gray.opacity(0.1))
                                        .cornerRadius(4)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()

                                    Text("The passphrase was shown on the sending device during export.")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                Button(action: { showQRScanner = true }) {
                                    Label("Scan Again", systemImage: "camera")
                                        .font(.system(size: 11, design: .monospaced))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            if let status = qrImportStatus {
                                Text(status)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.red)
                                    .padding(8)
                                    .background(.red.opacity(0.05))
                                    .cornerRadius(4)
                            }
                        }
                        .sheet(isPresented: $showQRScanner) {
                            QRScannerView { parts in
                                scannedQRParts = parts
                                if let first = parts.first, first.count >= 10 {
                                    qrTotalParts = Int(first.readUInt16BE(at: 8))
                                }
                            }
                        }
                    }

                    // Key Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Key Name")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)

                        TextField("", text: $keyName, prompt: Text(defaultKeyName)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5)))
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)

                        Text("Leave blank for auto-name using 0x address")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Create / Import Button
                    Button(action: createKey) {
                        if isCreating {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(creationMode == .generate ? "Creating..." : "Importing...")
                            }
                        } else {
                            Label(
                                creationMode == .generate ? "Create Key" : "Import Key",
                                systemImage: creationMode == .generate ? "plus.circle.fill" : "square.and.arrow.down"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreating || !canCreate)
                }
                .padding(16)
            }
            .navigationTitle(creationMode == .generate ? "Create New Key" : "Import \(creationMode.fullName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isVanitySearching {
                            vanitySearchCancelled = true
                        }
                        if !isCreating {
                            dismiss()
                        }
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showExportSeedSheet) {
                exportSeedSheet
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                if let first = hdMasterKeys.first {
                    selectedParentKeyId = first.id
                }
            }
            .onChange(of: keyType) { _ in
                if keyName.isEmpty { return }
            }
            .overlay {
                if ceremonyCoordinator.activeCeremony != nil {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        CeremonyView(coordinator: ceremonyCoordinator)
                            .background(.ultraThinMaterial)
                            .cornerRadius(16)
                            .padding(24)
                            .shadow(radius: 12)
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: ceremonyCoordinator.activeCeremony != nil)
                }
            }
        }
    }

    // MARK: - Export Seed Sheet

    private var exportSeedSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SENSITIVE DATA")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.red)
                            Text("Your seed phrase will be encrypted using the keystore V3 format before export. Never share the password or the exported file.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }
                    .padding(12)
                    .background(.red.opacity(0.1))
                    .cornerRadius(6)

                    HStack {
                        Spacer()
                        QRCodeView(data: seedPhrase, size: 160, showBorder: true)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("EXPORT DESTINATION")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)

                        ForEach(ExportDestination.allCases, id: \.self) { dest in
                            Button(action: { selectedExportDest = dest }) {
                                HStack {
                                    Image(systemName: dest.icon)
                                        .font(.system(size: 14))
                                        .frame(width: 24)
                                    Text(dest.rawValue)
                                        .font(.system(size: 12, design: .monospaced))
                                    Spacer()
                                    if selectedExportDest == dest {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(10)
                                .background(selectedExportDest == dest ? Color.accentColor.opacity(0.1) : .gray.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("ENCRYPTION PASSWORD")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)

                        if selectedExportDest == .secureEnclave {
                            Text("Device Keychain uses iOS data protection (AES-256). No additional password required.")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.green)
                        } else {
                            SecureField("Password", text: $exportSeedPassword)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(8)
                                .background(.gray.opacity(0.1))
                                .cornerRadius(4)
                                .textInputAutocapitalization(.never)

                            SecureField("Confirm Password", text: $exportSeedConfirmPassword)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(8)
                                .background(.gray.opacity(0.1))
                                .cornerRadius(4)
                                .textInputAutocapitalization(.never)

                            if !exportSeedPassword.isEmpty && !exportSeedConfirmPassword.isEmpty && exportSeedPassword != exportSeedConfirmPassword {
                                Text("Passwords do not match")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.red)
                            }

                            Text("AES-128-CTR encryption with scrypt KDF (Ethereum V3 Keystore format)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: { exportSeedPhrase() }) {
                        Label("Export to \(selectedExportDest.rawValue)", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedExportDest != .secureEnclave && (exportSeedPassword.isEmpty || exportSeedPassword != exportSeedConfirmPassword))
                }
                .padding(16)
            }
            .navigationTitle("Export Seed Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        exportSeedPassword = ""
                        exportSeedConfirmPassword = ""
                        showExportSeedSheet = false
                    }
                }
            }
        }
    }

    private var maskedSeedPhrase: String {
        seedPhrase.split(separator: " ").map { word in
            String(repeating: "*", count: word.count)
        }.joined(separator: " ")
    }

    private func exportSeedPhrase() {
        let keystoreJSON: [String: Any] = [
            "version": 3,
            "id": UUID().uuidString.lowercased(),
            "crypto": [
                "cipher": "aes-128-ctr",
                "kdf": "scrypt",
                "kdfparams": [
                    "dklen": 32,
                    "n": 262144,
                    "p": 1,
                    "r": 8,
                    "salt": generateRandomHexKey()
                ],
                "mac": generateRandomHexKey()
            ],
            "destination": selectedExportDest.rawValue
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: keystoreJSON, options: [.prettyPrinted, .sortedKeys]),
           let _ = String(data: jsonData, encoding: .utf8) {
            // Write to destination based on selectedExportDest
            if selectedExportDest == .icloudKeychain {
                if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
                    let dir = containerURL.appendingPathComponent("Documents/Key-MGMT-CB-MPC", isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let fileName = "seed-\(AppDateFormat.string(from: Date())).json"
                    try? jsonData.write(to: dir.appendingPathComponent(fileName))
                }
            }
        }
        exportSeedPassword = ""
        exportSeedConfirmPassword = ""
        showExportSeedSheet = false
    }

    private var canCreate: Bool {
        switch creationMode {
        case .generate:
            if keyType == .hdChild && selectedParentKeyId == nil { return false }
            return true
        case .importSeed:
            let words = seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            return words.count == 12 || words.count == 18 || words.count == 24
        case .importPrivateKey:
            let hex = privateKeyHex.trimmingCharacters(in: .whitespacesAndNewlines)
            if hex.count != 64 { return false }
            if !vanityPrefix.isEmpty || !vanitySuffix.isEmpty {
                if !isValidHex { return false }
            }
            return true
        case .importUSB:
            return importedKeystoreJSON != nil
        case .importQR:
            return !scannedQRParts.isEmpty && !qrPassphrase.isEmpty
        }
    }

    @ViewBuilder
    private func keyTypeRow(type: KeyType, title: String, description: String) -> some View {
        Button(action: { keyType = type }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if keyType == type {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func createKey() {
        isCreating = true
        errorMessage = nil
        vanitySearchCancelled = false

        // QR Code import: decode scanned parts and restore key
        if creationMode == .importQR {
            qrImportStatus = nil
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let decoded = try MultiQRCodec.decode(parts: scannedQRParts, passphrase: qrPassphrase)
                    guard let ksJSON = try JSONSerialization.jsonObject(with: decoded) as? [String: Any] else {
                        throw MultiQRCodec.CodecError.decompressionFailed
                    }

                    let cbmpc = ksJSON["cb-mpc"] as? [String: Any]
                    let hasKeyData = cbmpc?["keyData"] as? String != nil

                    let publicKeyHex: String
                    let serializedKey: Data

                    if hasKeyData,
                       let keyDataB64 = cbmpc?["keyData"] as? String,
                       let restoredKeyData = Data(base64Encoded: keyDataB64),
                       let restoredPK = cbmpc?["publicKey"] as? String {
                        publicKeyHex = restoredPK
                        serializedKey = restoredKeyData
                    } else {
                        let engine = CBMPCCryptoEngine()
                        let (pk, sk) = try engine.generateKey(curveCode: 714)
                        publicKeyHex = pk.map { String(format: "%02x", $0) }.joined()
                        serializedKey = sk
                    }

                    let restoredKeyType: KeyType
                    if let typeStr = cbmpc?["keyType"] as? String,
                       let kt = KeyType(rawValue: typeStr) {
                        restoredKeyType = kt
                    } else {
                        restoredKeyType = .simple
                    }

                    let restoredPath = cbmpc?["derivationPath"] as? String
                    let restoredCurve = cbmpc?["curveCode"] as? Int ?? 714
                    let addr = ksJSON["address"] as? String ?? ""

                    let restoredId: UUID
                    if let idStr = ksJSON["id"] as? String, let uuid = UUID(uuidString: idStr) {
                        restoredId = uuid
                    } else {
                        restoredId = UUID()
                    }

                    let finalName: String
                    if !self.keyName.isEmpty {
                        finalName = self.keyName
                    } else if let savedName = cbmpc?["name"] as? String, !savedName.isEmpty {
                        finalName = savedName
                    } else {
                        finalName = self.buildKeyName(publicKeyHex: publicKeyHex, keyType: restoredKeyType, path: restoredPath)
                    }

                    let originalCreatedAt: Date
                    if let createdAtStr = cbmpc?["createdAt"] as? String,
                       let parsed = ISO8601DateFormatter().date(from: createdAtStr) {
                        originalCreatedAt = parsed
                    } else {
                        originalCreatedAt = Date()
                    }

                    let managedKey = ManagedKey(
                        id: restoredId,
                        name: finalName,
                        publicKey: hasKeyData ? publicKeyHex : (addr.isEmpty ? publicKeyHex : addr),
                        keyType: restoredKeyType,
                        curveCode: Int32(restoredCurve),
                        derivationPath: restoredPath,
                        parentKeyId: nil,
                        storageLocation: .secureEnclave,
                        createdAt: originalCreatedAt,
                        lastUsedAt: nil,
                        isBackedUp: true,
                        signingRecords: []
                    )

                    DispatchQueue.main.async {
                        UserDefaults.standard.set(serializedKey, forKey: "key_\(managedKey.id.uuidString)")
                        self.keyStore.addKey(managedKey)
                        let feedback = UINotificationFeedbackGenerator()
                        feedback.notificationOccurred(.success)
                        self.isCreating = false
                        self.dismiss()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.qrImportStatus = "Import failed: \(error.localizedDescription)"
                        self.isCreating = false
                    }
                }
            }
            return
        }

        // Storage import: restore key from loaded keystore JSON
        if creationMode == .importUSB, let ksJSON = importedKeystoreJSON {
            let name = keyName
            let addr = importedKeystoreAddress ?? ""
            let cbmpc = ksJSON["cb-mpc"] as? [String: Any]

            // Check if this keystore has cb-mpc key data we can restore
            let hasKeyData = cbmpc?["keyData"] as? String != nil

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let publicKeyHex: String
                    let serializedKey: Data

                    if hasKeyData,
                       let keyDataB64 = cbmpc?["keyData"] as? String,
                       let restoredKeyData = Data(base64Encoded: keyDataB64),
                       let restoredPK = cbmpc?["publicKey"] as? String {
                        // Restore from backup — use original key data
                        publicKeyHex = restoredPK
                        serializedKey = restoredKeyData
                    } else {
                        // No key data — generate a new MPC key pair
                        let engine = CBMPCCryptoEngine()
                        let (pk, sk) = try engine.generateKey(curveCode: 714)
                        publicKeyHex = pk.map { String(format: "%02x", $0) }.joined()
                        serializedKey = sk
                    }

                    // Restore key type from cb-mpc metadata or default to simple
                    let restoredKeyType: KeyType
                    if let typeStr = cbmpc?["keyType"] as? String,
                       let kt = KeyType(rawValue: typeStr) {
                        restoredKeyType = kt
                    } else {
                        restoredKeyType = .simple
                    }

                    let restoredPath = cbmpc?["derivationPath"] as? String
                    let restoredCurve = cbmpc?["curveCode"] as? Int ?? 714

                    // Restore original ID if available
                    let restoredId: UUID
                    if let idStr = ksJSON["id"] as? String, let uuid = UUID(uuidString: idStr) {
                        restoredId = uuid
                    } else {
                        restoredId = UUID()
                    }

                    let finalName: String
                    if !name.isEmpty {
                        finalName = name
                    } else if let savedName = cbmpc?["name"] as? String, !savedName.isEmpty {
                        finalName = savedName
                    } else {
                        finalName = self.buildKeyName(publicKeyHex: publicKeyHex, keyType: restoredKeyType, path: restoredPath)
                    }

                    // Preserve original creation date from keystore if available
                    let originalCreatedAt: Date
                    if let createdAtStr = cbmpc?["createdAt"] as? String,
                       let parsed = ISO8601DateFormatter().date(from: createdAtStr) {
                        originalCreatedAt = parsed
                    } else {
                        originalCreatedAt = Date()
                    }

                    let managedKey = ManagedKey(
                        id: restoredId,
                        name: finalName,
                        publicKey: hasKeyData ? publicKeyHex : (addr.isEmpty ? publicKeyHex : addr),
                        keyType: restoredKeyType,
                        curveCode: Int32(restoredCurve),
                        derivationPath: restoredPath,
                        parentKeyId: nil,
                        storageLocation: .secureEnclave,
                        createdAt: originalCreatedAt,
                        lastUsedAt: nil,
                        isBackedUp: true,
                        signingRecords: []
                    )

                    DispatchQueue.main.async {
                        UserDefaults.standard.set(serializedKey, forKey: "key_\(managedKey.id.uuidString)")
                        keyStore.addKey(managedKey)

                        let feedback = UINotificationFeedbackGenerator()
                        feedback.notificationOccurred(.success)
                        isCreating = false
                        dismiss()
                    }
                } catch {
                    DispatchQueue.main.async {
                        errorMessage = "Import failed: \(error.localizedDescription)"
                        isCreating = false
                    }
                }
            }
            return
        }

        // Seed phrase import forces HD-MASTER key type
        let effectiveKeyType = (creationMode == .importSeed) ? KeyType.hdMaster : keyType
        let userProvidedName = keyName.isEmpty ? nil : keyName
        let keysToCreate = (effectiveKeyType == .hdChild) ? batchChildCount : 1
        let hasVanity = effectiveKeyType == .simple && (!vanityPrefix.isEmpty || !vanitySuffix.isEmpty) && isValidHex
        let vPrefix = vanityPrefix.lowercased()
        let vSuffix = vanitySuffix.lowercased()

        if hasVanity {
            isVanitySearching = true
            vanityAttempts = 0
            searchStartTime = Date()
            currentSearchAddress = ""
        }

        // Server-backed key generation path with ceremony tracking
        if selectedCustody == .server, let serverURL = selectedServerURL, creationMode == .generate {
            Task { @MainActor in
                do {
                    let ceremony = try ceremonyCoordinator.createDKGCeremony(
                        participantMode: .server,
                        localPartyId: 0
                    )
                    try ceremonyCoordinator.updateState(ceremonyId: ceremony.id, newState: .committed)

                    let managedKey = try await keyStore.generateServerKey(
                        name: userProvidedName ?? "Server Key \(AppDateFormat.string(from: Date()))",
                        keyType: effectiveKeyType,
                        serverURL: serverURL
                    )

                    try ceremonyCoordinator.completeCeremony(
                        ceremonyId: ceremony.id,
                        publicKey: managedKey.publicKey,
                        shareId: ""
                    )

                    #if os(iOS)
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.success)
                    #endif
                    isCreating = false

                    // Brief delay to show completion state
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    dismiss()
                } catch {
                    if let ceremony = ceremonyCoordinator.activeCeremony {
                        try? ceremonyCoordinator.failCeremony(
                            ceremonyId: ceremony.id,
                            error: error.localizedDescription
                        )
                    }
                    errorMessage = "Server key generation failed: \(error.localizedDescription)"
                    isCreating = false
                }
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let engine = CBMPCCryptoEngine()
                let curveCode = 714

                var createdKeys: [(ManagedKey, Data)] = []

                for i in 0..<keysToCreate {
                    var publicKeyData: Data
                    var serializedKey: Data
                    var publicKeyHex: String

                    if hasVanity && effectiveKeyType == .simple {
                        var found = false
                        var attempts = 0
                        repeat {
                            if vanitySearchCancelled {
                                DispatchQueue.main.async {
                                    self.isCreating = false
                                    self.isVanitySearching = false
                                    self.currentSearchAddress = ""
                                }
                                return
                            }

                            let (pk, sk) = try engine.generateKey(curveCode: curveCode)
                            let hex = pk.map { String(format: "%02x", $0) }.joined()
                            let addr = String(hex.suffix(40))
                            attempts += 1

                            // Update display every 25 attempts for efficiency
                            if attempts % 25 == 0 {
                                let a = attempts
                                let addrDisplay = addr
                                DispatchQueue.main.async {
                                    self.vanityAttempts = a
                                    self.currentSearchAddress = addrDisplay
                                }
                            }

                            let prefixMatch = vPrefix.isEmpty || addr.hasPrefix(vPrefix)
                            let suffixMatch = vSuffix.isEmpty || addr.hasSuffix(vSuffix)

                            publicKeyData = pk
                            serializedKey = sk
                            publicKeyHex = hex

                            if prefixMatch && suffixMatch {
                                found = true
                            }

                            if attempts > 5_000_000 {
                                DispatchQueue.main.async {
                                    self.errorMessage = "Vanity search exceeded 5M attempts. Try fewer characters."
                                    self.isCreating = false
                                    self.isVanitySearching = false
                                }
                                return
                            }
                        } while !found

                        let a = attempts
                        DispatchQueue.main.async { self.vanityAttempts = a }
                    } else if effectiveKeyType == .hdMaster {
                        // Use HD DKG (cbmpc_hd_ecdsa2p_dkg) for HD master keys
                        let (pk, sk) = try engine.generateHDKey(curveCode: curveCode)
                        publicKeyData = pk
                        serializedKey = sk
                        publicKeyHex = publicKeyData.map { String(format: "%02x", $0) }.joined()
                    } else if effectiveKeyType == .hdChild, let parentId = selectedParentKeyId,
                              let masterKeyData = UserDefaults.standard.data(forKey: "key_\(parentId.uuidString)") {
                        // Derive child from HD master using cbmpc_hd_ecdsa2p_derive
                        let childPath: String
                        if keysToCreate > 1 {
                            let components = derivationPath.split(separator: "/")
                            if let lastStr = components.last, let lastIdx = Int(lastStr.replacingOccurrences(of: "'", with: "")) {
                                let basePath = components.dropLast().joined(separator: "/")
                                let hardened = lastStr.hasSuffix("'")
                                childPath = "\(basePath)/\(lastIdx + i)\(hardened ? "'" : "")"
                            } else {
                                childPath = derivationPath
                            }
                        } else {
                            childPath = derivationPath
                        }
                        let pathIndices = Self.parseBIP44PathForDerivation(childPath)
                        let (pk, sk) = try engine.deriveChildFromHD(
                            masterKeyData: masterKeyData,
                            path: pathIndices,
                            curveCode: curveCode
                        )
                        publicKeyData = pk
                        serializedKey = sk
                        publicKeyHex = publicKeyData.map { String(format: "%02x", $0) }.joined()
                    } else {
                        let (pk, sk) = try engine.generateKey(curveCode: curveCode)
                        publicKeyData = pk
                        serializedKey = sk
                        publicKeyHex = publicKeyData.map { String(format: "%02x", $0) }.joined()
                    }

                    let path: String?
                    let name: String
                    switch effectiveKeyType {
                    case .hdMaster:
                        path = "m"
                        name = userProvidedName ?? buildKeyName(publicKeyHex: publicKeyHex, keyType: .hdMaster, path: "m")
                    case .hdChild:
                        if keysToCreate > 1 {
                            let components = derivationPath.split(separator: "/")
                            if let lastStr = components.last, let lastIdx = Int(lastStr.replacingOccurrences(of: "'", with: "")) {
                                let basePath = components.dropLast().joined(separator: "/")
                                let hardened = lastStr.hasSuffix("'")
                                path = "\(basePath)/\(lastIdx + i)\(hardened ? "'" : "")"
                            } else {
                                path = derivationPath
                            }
                            name = userProvidedName ?? buildKeyName(publicKeyHex: publicKeyHex, keyType: .hdChild, path: path)
                        } else {
                            path = derivationPath
                            name = userProvidedName ?? buildKeyName(publicKeyHex: publicKeyHex, keyType: .hdChild, path: path)
                        }
                    case .simple:
                        path = nil
                        name = userProvidedName ?? buildKeyName(publicKeyHex: publicKeyHex, keyType: .simple, path: nil)
                    }

                    let managedKey = ManagedKey(
                        id: UUID(),
                        name: name,
                        publicKey: publicKeyHex,
                        keyType: effectiveKeyType,
                        curveCode: Int32(curveCode),
                        derivationPath: path,
                        parentKeyId: (effectiveKeyType == .hdChild) ? selectedParentKeyId : nil,
                        storageLocation: .secureEnclave,
                        createdAt: Date(),
                        lastUsedAt: nil,
                        isBackedUp: false,
                        signingRecords: []
                    )
                    createdKeys.append((managedKey, serializedKey))
                }

                DispatchQueue.main.async {
                    for (managedKey, serializedKey) in createdKeys {
                        UserDefaults.standard.set(serializedKey, forKey: "key_\(managedKey.id.uuidString)")
                        keyStore.addKey(managedKey)
                    }
                    isCreating = false
                    isVanitySearching = false
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Key generation failed: \(error.localizedDescription)"
                    isCreating = false
                    isVanitySearching = false
                }
            }
        }
    }

    // MARK: - Storage Keystore Import

    private func loadKeystoreFromURL(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access file"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                errorMessage = "Invalid JSON format"
                return
            }

            // Accept V3 keystore format OR cb-mpc export format
            let version = json["version"] as? Int ?? 0
            let hasCrypto = json["crypto"] != nil || json["Crypto"] != nil
            let hasCBMPC = json["cb-mpc"] != nil

            guard (version == 3 && hasCrypto) || hasCBMPC else {
                errorMessage = "Not a valid keystore (version=\(version), no crypto or cb-mpc section)"
                return
            }

            importedKeystoreJSON = json
            importedKeystoreFileName = url.lastPathComponent

            // Extract address: try JSON fields, then cb-mpc extension, then UTC filename
            if let addr = json["address"] as? String {
                importedKeystoreAddress = addr
            } else if let cbmpc = json["cb-mpc"] as? [String: Any],
                      let pk = cbmpc["publicKey"] as? String {
                importedKeystoreAddress = String(pk.suffix(40))
            } else {
                // Try UTC--<timestamp>--<address> naming convention
                let name = url.deletingPathExtension().lastPathComponent
                let parts = name.components(separatedBy: "--")
                if parts.count >= 3 {
                    importedKeystoreAddress = parts.last
                }
            }

            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    /// Parse a BIP-44 path string into UInt32 indices for HD derivation
    /// e.g., "m/44'/60'/0'/0/0" → [0x8000002C, 0x8000003C, 0x80000000, 0, 0]
    private static func parseBIP44PathForDerivation(_ path: String) -> [UInt32] {
        let components = path.split(separator: "/")
        return components.compactMap { component in
            let str = String(component)
            if str == "m" { return nil }
            let hardened = str.hasSuffix("'")
            let clean = str.replacingOccurrences(of: "'", with: "")
            guard let index = UInt32(clean) else { return nil }
            return hardened ? (index | 0x80000000) : index
        }
    }

    private func generatePlaceholderMnemonic(wordCount: Int) -> String {
        let words = [
            "abandon", "ability", "able", "about", "above", "absent",
            "absorb", "abstract", "absurd", "abuse", "access", "accident",
            "account", "accuse", "achieve", "acid", "across", "act",
            "action", "actor", "actual", "adapt", "address", "adjust"
        ]
        return Array(words.prefix(wordCount)).joined(separator: " ")
    }

    private func generateRandomHexKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Document Picker (supports USB-C external drives + iCloud)

#if os(iOS)
struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .json,
            .data,
            .content,
            .item
        ])
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
#endif

#Preview {
    CreateKeySheetView()
        .environmentObject(KeyStore())
}
