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
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        } else {
                            Text("Tap + to create a new key. Swipe left to delete.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        }
                    }
                    .listSectionSpacing(.compact)
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
                            KeyListItemView(key: key, isNew: key.id == keyStore.recentlyAddedKeyId)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let key = keyStore.keys[index]
                            keyStore.deleteKey(key.id)
                        }
                    }
                    .onMove { source, destination in
                        keyStore.moveKeys(from: source, to: destination)
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
    var isNew: Bool = false

    @State private var highlightVisible = true

    private var hasKeyData: Bool {
        UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") != nil
    }

    private var origin: TransportOrigin {
        TransportOrigin.load(for: key.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Line 1: Name + Valid key indicator
            HStack(spacing: 8) {
                Text(key.name)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(isNew && highlightVisible ? .blue : .primary)
                    .lineLimit(1)

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

            // Line 2: Key type + Custody badge
            HStack(spacing: 6) {
                Text(key.displayKeyType)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isNew && highlightVisible ? .blue.opacity(0.7) : .secondary)

                HStack(spacing: 3) {
                    Image(systemName: origin.shieldIcon)
                        .font(.system(size: 7))
                    Text(origin.badgeText)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                }
                .foregroundColor(origin.badgeColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(origin.badgeColor.opacity(0.1))
                .cornerRadius(3)

                Spacer()

                Text(key.shortAddress)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isNew && highlightVisible ? .blue.opacity(0.7) : .secondary)
            }
        }
        .padding(.vertical, 2)
        .background(isNew && highlightVisible ? Color.blue.opacity(0.08) : Color.clear)
        .animation(.easeInOut(duration: 0.6).repeatCount(5, autoreverses: true), value: highlightVisible)
        .onAppear {
            if isNew {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    highlightVisible = false
                }
            }
        }
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
