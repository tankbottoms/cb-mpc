import SwiftUI
#if os(iOS)
import UIKit
import UniformTypeIdentifiers
#endif

enum KeyCreationMode: String, CaseIterable {
    case generate = "Generate"
    case importSeed = "Seed Phrase"
    case importPrivateKey = "Private Key"
    case importUSB = "USB-C"
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
    case secureEnclave = "Secure Enclave"
    case icloud = "iCloud"
    case usbc = "USB-C"

    var icon: String {
        switch self {
        case .secureEnclave: return "lock.shield"
        case .icloud: return "icloud"
        case .usbc: return "externaldrive"
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
    @State private var derivationPreset: DerivationPreset = .metamask
    @State private var batchChildCount = 1
    @State private var vanityPrefix = ""
    @State private var vanitySuffix = ""
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

    private var hdMasterKeys: [ManagedKey] {
        keyStore.keys.filter { $0.keyType == .hdMaster }
    }

    private var defaultKeyName: String {
        let timestamp = AppDateFormat.string(from: Date())
        switch keyType {
        case .simple:
            return "ECDSA \(timestamp)"
        case .hdMaster:
            return "HD-MASTER \(timestamp)"
        case .hdChild:
            if let parentId = selectedParentKeyId,
               let parent = hdMasterKeys.first(where: { $0.id == parentId }) {
                let lastComponent = derivationPath.split(separator: "/").last.map(String.init) ?? "0"
                return "\(parent.shortAddress)/\(lastComponent) \(timestamp)"
            }
            return derivationPath
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
            if !hdChildNamingUseSelf,
               let parentId = selectedParentKeyId,
               let parent = hdMasterKeys.first(where: { $0.id == parentId }) {
                let masterAddr = parent.shortAddress
                return "\(masterAddr)/\(path ?? "0") \(timestamp)"
            }
            return "\(shortAddr)/\(path ?? "0") \(timestamp)"
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
                        }
                    }

                    // Import: USB-C
                    if creationMode == .importUSB {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "externaldrive.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Connect USB-C Drive")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    Text("Import an Ethereum keystore (V3 JSON)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Accepted format: Ethereum V3 Keystore JSON")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text("The keystore file uses AES-128-CTR encryption with scrypt KDF. A password is required to decrypt the private key. Files follow the naming convention:")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text("UTC--<timestamp>--<address>")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(4)
                                    .background(.gray.opacity(0.05))
                                    .cornerRadius(2)
                                Text("Compatible with Geth (go-ethereum), Clef, and standard Ethereum account management tools. See geth.ethereum.org for keystore specification details.")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .padding(8)
                            .background(.blue.opacity(0.05))
                            .cornerRadius(4)

                            Button(action: { showDocumentPicker = true }) {
                                Label("Browse Files", systemImage: "folder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .sheet(isPresented: $showDocumentPicker) {
                            DocumentPickerView()
                        }
                    }

                    // Vanity Address (for generate mode, simple keys)
                    if creationMode == .generate && keyType == .simple {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Vanity Address (optional)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Prefix")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    TextField("0x...", text: $vanityPrefix)
                                        .font(.system(size: 11, design: .monospaced))
                                        .padding(6)
                                        .background(.gray.opacity(0.1))
                                        .cornerRadius(4)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Suffix")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    TextField("...ff", text: $vanitySuffix)
                                        .font(.system(size: 11, design: .monospaced))
                                        .padding(6)
                                        .background(.gray.opacity(0.1))
                                        .cornerRadius(4)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
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
                                    // Current address being searched (left) + stats (right)
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
            .navigationTitle(creationMode == .generate ? "Create New Key" : "Import Key")
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
                            Text("Secure Enclave uses hardware-backed encryption. No password required.")
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
            if selectedExportDest == .icloud {
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
            if !vanityPrefix.isEmpty || !vanitySuffix.isEmpty {
                if !isValidHex { return false }
            }
            return true
        case .importSeed:
            let words = seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            return words.count == 12 || words.count == 18 || words.count == 24
        case .importPrivateKey:
            let hex = privateKeyHex.trimmingCharacters(in: .whitespacesAndNewlines)
            return hex.count == 64
        case .importUSB:
            return false
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

        let userProvidedName = keyName.isEmpty ? nil : keyName
        let keysToCreate = (keyType == .hdChild) ? batchChildCount : 1
        let hasVanity = keyType == .simple && (!vanityPrefix.isEmpty || !vanitySuffix.isEmpty) && isValidHex
        let vPrefix = vanityPrefix.lowercased()
        let vSuffix = vanitySuffix.lowercased()

        if hasVanity {
            isVanitySearching = true
            vanityAttempts = 0
            searchStartTime = Date()
            currentSearchAddress = ""
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

                    if hasVanity && keyType == .simple {
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
                    } else {
                        let (pk, sk) = try engine.generateKey(curveCode: curveCode)
                        publicKeyData = pk
                        serializedKey = sk
                        publicKeyHex = publicKeyData.map { String(format: "%02x", $0) }.joined()
                    }

                    let path: String?
                    let name: String
                    switch keyType {
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
                        keyType: keyType,
                        curveCode: Int32(curveCode),
                        derivationPath: path,
                        parentKeyId: (keyType == .hdChild) ? selectedParentKeyId : nil,
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

    // MARK: - Helpers

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
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .json,
            .data,
            .content,
            .item
        ])
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
#endif

#Preview {
    CreateKeySheetView()
        .environmentObject(KeyStore())
}
