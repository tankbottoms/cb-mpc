import SwiftUI

struct CreateKeySheetView: View {
    @EnvironmentObject var keyStore: KeyStore
    @Environment(\.dismiss) var dismiss

    @State private var keyName = "My Key"
    @State private var keyType: KeyType = .simple
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var derivationPath = "m/44'/60'/0'/0/0"
    @State private var selectedParentKeyId: UUID?

    private var hdMasterKeys: [ManagedKey] {
        keyStore.keys.filter { $0.keyType == .hdMaster }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Key Name")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    TextField("Key Name", text: $keyName)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Key Type")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    VStack(spacing: 0) {
                        keyTypeRow(
                            type: .simple,
                            title: "Simple Key",
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

                if keyType == .hdChild {
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
                    }
                }

                Spacer()

                Button(action: createKey) {
                    if isCreating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Creating...")
                        }
                    } else {
                        Label("Create Key", systemImage: "plus.circle.fill")
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .disabled(isCreating || keyName.isEmpty || (keyType == .hdChild && selectedParentKeyId == nil))
            }
            .padding(16)
            .navigationTitle("Create New Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                if let first = hdMasterKeys.first {
                    selectedParentKeyId = first.id
                }
            }
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

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let engine = CBMPCCryptoEngine()
                let curveCode = 714
                let (publicKey, serializedKey) = try engine.generateKey(curveCode: curveCode)

                DispatchQueue.main.async {
                    let publicKeyHex = publicKey.map { String(format: "%02x", $0) }.joined()

                    let path: String?
                    switch keyType {
                    case .hdMaster:
                        path = "m"
                    case .hdChild:
                        path = derivationPath
                    case .simple:
                        path = nil
                    }

                    let managedKey = ManagedKey(
                        id: UUID(),
                        name: keyName,
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
                    UserDefaults.standard.set(serializedKey, forKey: "key_\(managedKey.id.uuidString)")
                    keyStore.addKey(managedKey)
                    isCreating = false
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Key generation failed: \(error.localizedDescription)"
                    isCreating = false
                }
            }
        }
    }
}

#Preview {
    CreateKeySheetView()
        .environmentObject(KeyStore())
}
