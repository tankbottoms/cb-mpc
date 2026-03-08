import SwiftUI

struct KeyDashboardView: View {
    @EnvironmentObject var keyStore: KeyStore
    @State private var showCreateKeySheet = false
    @AppStorage("instructionLevel") private var instructionLevel = "verbose"

    var body: some View {
        NavigationStack {
            List {
                // Instructions section
                if instructionLevel != "off" {
                    Section {
                        if instructionLevel == "verbose" {
                            Text("Keys are generated using distributed key generation (DKG) with two MPC shares. The private key never exists in a single location. Use Standard ECDSA for general signing, HD Master to create a key hierarchy, or HD Child for derived wallet addresses.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Tap + to create a new key. Swipe left to delete.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if keyStore.keys.isEmpty {
                    #if os(macOS)
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "key.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Keys")
                            .font(.headline)
                        Text("Create your first key to get started")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    #else
                    ContentUnavailableView(
                        "No Keys",
                        systemImage: "key.slash",
                        description: Text("Create your first key to get started")
                    )
                    #endif
                } else {
                    ForEach(keyStore.keys) { key in
                        NavigationLink(destination: KeyDetailView(key: key)) {
                            KeyListItemView(key: key)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let key = keyStore.keys[index]
                            keyStore.deleteKey(key.id)
                        }
                    }
                }
            }
            .navigationTitle("Keys")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showCreateKeySheet = true }) {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showCreateKeySheet) {
                CreateKeySheetView()
                    .environmentObject(keyStore)
            }
        }
    }
}

struct KeyListItemView: View {
    let key: ManagedKey

    private var hasKeyData: Bool {
        UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Line 1: Name + Valid key indicator
            HStack(spacing: 8) {
                Text(key.name)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))

                Spacer()

                if hasKeyData {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            // Line 2: Public Key + Type
            HStack(spacing: 12) {
                Text(key.publicKey.prefix(32).map { String($0) }.joined() + "...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Text(key.displayKeyType)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
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
        lastUsedAt: Date().addingTimeInterval(-3600),
        isBackedUp: true
    )

    return KeyListItemView(key: mockKey)
}
