import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct KeyDetailView: View {
    let key: ManagedKey
    @EnvironmentObject var keyStore: KeyStore
    @State private var showSigningSheet = false
    @State private var showVerifySheet = false
    @State private var showExportSheet = false
    @State private var showQRSheet = false

    private var hasKeyData: Bool {
        UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.name)
                            .font(.system(.headline, design: .monospaced))
                        Text(key.keyType.rawValue.uppercased())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        if key.isBackedUp {
                            Label("Synced", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }

                    Spacer()

                    // QR Code in top-right (3x larger)
                    Button(action: { showQRSheet = true }) {
                        QRCodeView(data: key.publicKey, size: 144)
                            .frame(width: 144, height: 144)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)

                // Public Key Display
                VStack(alignment: .leading, spacing: 6) {
                    Text("Public Key")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text(key.publicKey)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(4)

                    HStack(spacing: 6) {
                        Button(action: { copyToClipboard(key.publicKey) }) {
                            Text("Copy")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)

                        Button(action: { showQRSheet = true }) {
                            Text("QR Code")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
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
                        Text(key.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(.caption, design: .monospaced))
                    }

                    if let lastUsed = key.lastUsedAt {
                        Divider()
                        HStack {
                            Text("Last Used")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastUsed.formatted(date: .abbreviated, time: .shortened))
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
                        Button(action: { showSigningSheet = true }) {
                            Label("Sign", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("No key data - regenerate this key to enable signing")
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
                            Button(action: {}) {
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
                    Text("Signing History")
                        .font(.system(.headline, design: .monospaced))

                    if key.signingRecords.isEmpty {
                        Text("No signing history")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(key.signingRecords.prefix(5)) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 9, design: .monospaced))
                                    Spacer()
                                    if record.verified {
                                        Label("Verified", systemImage: "checkmark.circle.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(.green)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("SHA-256")
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(record.messageHash)
                                        .font(.system(size: 8, design: .monospaced))
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                        .foregroundColor(.secondary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Signature")
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(record.signature)
                                        .font(.system(size: 8, design: .monospaced))
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                        .foregroundColor(.secondary)
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
        .sheet(isPresented: $showVerifySheet) {
            VerifySignatureSheetView(key: key)
        }
        .sheet(isPresented: $showQRSheet) {
            NavigationStack {
                VStack(spacing: 16) {
                    QRCodeView(data: key.publicKey, size: 280)
                        .padding()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Public Key")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)

                        Text(key.publicKey)
                            .font(.system(size: 8, design: .monospaced))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)

                        Button(action: { copyToClipboard(key.publicKey) }) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                    }
                    .padding(12)

                    Spacer()
                }
                .navigationTitle("QR Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showQRSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
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
        lastUsedAt: Date(),
        isBackedUp: true,
        signingRecords: []
    )

    return NavigationStack {
        KeyDetailView(key: mockKey)
            .environmentObject(KeyStore())
    }
}
