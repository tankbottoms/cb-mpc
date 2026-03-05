import SwiftUI

#if os(iOS)
import UIKit
#endif

// MARK: - Key Share Generation View

#if os(iOS)
@available(macOS 14.0, *)
struct KeyShareGenerationView: View {
    @State private var viewModel = KeyShareViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)

                    Text("Key Share Generation")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Generate a 2-party ECDSA key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Key Display
                if let keyShare = viewModel.keyShare {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Public Key Generated", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Public Key")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(keyShare.publicKey)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(3)
                                .truncationMode(.middle)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }

                        Button(action: {
                            UIPasteboard.general.string = keyShare.publicKey
                        }) {
                            Label("Copy Public Key", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                // Action Button
                Button(action: {
                    viewModel.generateKeyShare()
                }) {
                    if viewModel.isGenerating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Generating...")
                        }
                    } else {
                        Label("Generate Key Pair", systemImage: "plus.circle.fill")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(viewModel.isGenerating)

                Spacer()
            }
            .padding(16)
            .navigationTitle("Key Generation")
        }
    }
}
#endif // os(iOS)

// MARK: - Transaction Signing View

#if os(iOS)
@available(macOS 14.0, *)
struct TransactionSigningView: View {
    @State private var viewModel = SigningViewModel()
    @State private var messageInput = "Hello, blockchain!"

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "signature")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)

                    Text("Sign Transaction")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Sign a message with your 2-party key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Message Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Message")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $messageInput)
                        .frame(height: 80)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .border(Color.gray, width: 1)
                }

                // Signature Display
                if let transaction = viewModel.transaction {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Signed", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.headline)

                            Spacer()

                            if transaction.verified ?? false {
                                Label("Verified", systemImage: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Signature")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(transaction.signature ?? "")
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(3)
                                .truncationMode(.middle)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }

                        Button(action: {
                            UIPasteboard.general.string = transaction.signature
                        }) {
                            Label("Copy Signature", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                // Sign Button
                Button(action: {
                    viewModel.signMessage(messageInput)
                }) {
                    if viewModel.isSigning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Signing...")
                        }
                    } else {
                        Label("Sign Message", systemImage: "checkmark.circle.fill")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(viewModel.isSigning)

                Spacer()
            }
            .padding(16)
            .navigationTitle("Signing")
        }
    }
}
#endif // os(iOS)

// MARK: - Backup to USB View

#if os(iOS)
@available(macOS 14.0, *)
struct BackupUSBView: View {
    @State private var viewModel = BackupViewModel()
    @State private var keyShareVM = KeyShareViewModel()
    @State private var showExportAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)

                    Text("USB Backup")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Backup key share to external drive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Backup Status
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Backup Ready")
                                .font(.headline)
                            Text("Key share encryption enabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    Divider()

                    // Backup Details
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "Device", value: UIDevice.current.name)
                        DetailRow(label: "Public Key", value: "32 bytes")
                        DetailRow(label: "Share Size", value: "128 bytes")
                    }
                }
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Instructions")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        BackupStep(number: 1, title: "Connect USB-C Drive", description: "Connect an external USB-C storage device")
                        BackupStep(number: 2, title: "Export", description: "Tap 'Export to USB' below")
                        BackupStep(number: 3, title: "Secure", description: "Backup is encrypted with AES-256")
                    }
                }

                // Export Button
                Button(action: {
                    if let keyShare = keyShareVM.keyShare {
                        viewModel.prepareBackup(keyShare: keyShare)
                        showExportAlert = true
                    } else {
                        keyShareVM.generateKeyShare()
                    }
                }) {
                    if viewModel.isExporting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Exporting...")
                        }
                    } else {
                        Label("Export to USB", systemImage: "arrow.up.doc")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(viewModel.isExporting)

                Spacer()
            }
            .padding(16)
            .navigationTitle("Backup")
            .alert("Export Complete", isPresented: $showExportAlert) {
                Button("Done") {
                    showExportAlert = false
                }
            } message: {
                Text("Backup exported successfully to USB drive")
            }
        }
    }
}
#endif // os(iOS)

// MARK: - Helper Views

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
    }
}

struct BackupStep: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

#if os(iOS)
#Preview {
    if #available(macOS 14.0, *) {
        TabView {
            KeyShareGenerationView()
                .tabItem {
                    Label("Key Share", systemImage: "key.fill")
                }

            TransactionSigningView()
                .tabItem {
                    Label("Sign", systemImage: "signature")
                }

            BackupUSBView()
                .tabItem {
                    Label("Backup", systemImage: "externaldrive.fill")
                }
        }
    } else {
        Text("Preview not available on this macOS version")
    }
}
#endif // os(iOS)
