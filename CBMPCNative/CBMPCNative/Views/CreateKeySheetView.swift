import SwiftUI

struct CreateKeySheetView: View {
    @EnvironmentObject var keyStore: KeyStore
    @Environment(\.dismiss) var dismiss

    @State private var keyName = "My Key"
    @State private var keyType: KeyType = .simple
    @State private var isCreating = false
    @State private var errorMessage: String?

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

                    Picker("Key Type", selection: $keyType) {
                        Text("Simple Key").tag(KeyType.simple)
                        // HD Master support coming soon
                        // Text("HD Master").tag(KeyType.hdMaster)
                    }
                    .pickerStyle(.segmented)
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
                .disabled(isCreating || keyName.isEmpty)
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
        }
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
                    let managedKey = ManagedKey(
                        id: UUID(),
                        name: keyName,
                        publicKey: publicKeyHex,
                        keyType: keyType,
                        curveCode: Int32(curveCode),
                        derivationPath: (keyType == .hdMaster) ? "m" : nil,
                        parentKeyId: nil,
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
