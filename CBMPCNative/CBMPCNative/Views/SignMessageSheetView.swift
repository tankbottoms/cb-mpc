import SwiftUI
import CryptoKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct SignMessageSheetView: View {
    let key: ManagedKey
    @EnvironmentObject var keyStore: KeyStore
    @Environment(\.dismiss) var dismiss

    @State private var message = "Hello, blockchain!"
    @State private var nonce = UUID().uuidString
    @State private var isSigning = false
    @State private var signature: String?
    @AppStorage("signingServerURL") private var signingServerURL = "https://server/submit"
    @State private var showServerSubmitSheet = false
    @State private var serverSubmitInProgress = false
    @State private var serverSubmitError: String?

    var messageHash: String {
        let data = message.data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Message Input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Message")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    TextEditor(text: $message)
                        .frame(height: 80)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(4)
                        .border(Color.gray, width: 1)
                }

                // Nonce Field
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Nonce")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { nonce = UUID().uuidString }) {
                            Text("Regenerate")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(nonce)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .padding(8)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }

                // Hash Display
                VStack(alignment: .leading, spacing: 6) {
                    Text("SHA-256 Hash")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text(messageHash)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .padding(8)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }

                // Signature Display (if signed)
                if let sig = signature {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Signature")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Label("Signed", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }

                        Text(sig)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .padding(8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)
                            .textSelection(.enabled)
                    }
                }

                Spacer()

                // Sign Button
                if signature == nil {
                    Button(action: signMessage) {
                        if isSigning {
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
                    .buttonStyle(.borderedProminent)
                    .disabled(isSigning)
                } else {
                    HStack(spacing: 8) {
                        Button(action: { copyToClipboard(signature ?? "") }) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if !signingServerURL.isEmpty && signingServerURL != "https://server/submit" {
                            Button(action: { showServerSubmitSheet = true }) {
                                if serverSubmitInProgress {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Submitting...")
                                    }
                                } else {
                                    Label("Submit", systemImage: "arrow.up.circle.fill")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.borderedProminent)
                            .disabled(serverSubmitInProgress)
                        } else {
                            Button(action: { dismiss() }) {
                                Label("Done", systemImage: "checkmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(12)
            .navigationTitle("Sign Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showServerSubmitSheet) {
            ServerSubmitResultView(
                nonce: nonce,
                signature: signature ?? "",
                publicKey: key.publicKey,
                message: message,
                serverURL: signingServerURL,
                isSubmitting: $serverSubmitInProgress,
                error: $serverSubmitError,
                onDismiss: { dismiss() }
            )
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

    private func signMessage() {
        isSigning = true

        // Include nonce in the signed message
        let messageWithNonce = "\(message)|\(nonce)"

        // Sign on main thread (KeyStore is MainActor)
        do {
            let sig = try keyStore.signMessage(messageWithNonce, with: key)
            self.signature = sig
            isSigning = false
        } catch {
            print("Signing failed: \(error)")
            isSigning = false
        }
    }
}

struct ServerSubmitResultView: View {
    let nonce: String
    let signature: String
    let publicKey: String
    let message: String
    let serverURL: String
    @Binding var isSubmitting: Bool
    @Binding var error: String?
    @Environment(\.dismiss) var dismiss
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Nonce
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Nonce")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { copyToClipboard(nonce) }) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(nonce)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .padding(8)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }

                // Signature
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Signature")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { copyToClipboard(signature) }) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(signature)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(4)
                        .truncationMode(.middle)
                        .padding(8)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }

                if let errorMsg = error {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Error")
                                .font(.caption)
                        }
                        Text(errorMsg)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(.red.opacity(0.1))
                    .cornerRadius(4)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: { dismiss(); onDismiss() }) {
                        Label("Done", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: submitToServer) {
                        if isSubmitting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Sending...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Submit", systemImage: "arrow.up.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)
                }
            }
            .padding(12)
            .navigationTitle("Submission")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss(); onDismiss() }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

    private func submitToServer() {
        isSubmitting = true
        error = nil

        Task {
            do {
                try await SigningServerClient.shared.submit(
                    nonce: nonce,
                    publicKey: publicKey,
                    signature: signature,
                    message: message,
                    serverURL: serverURL
                )
                DispatchQueue.main.async {
                    isSubmitting = false
                    dismiss()
                    onDismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

#Preview {
    let mockKey = ManagedKey(
        id: UUID(),
        name: "Test Key",
        publicKey: "02abc123",
        keyType: .simple,
        curveCode: 714,
        derivationPath: nil,
        parentKeyId: nil,
        storageLocation: .secureEnclave,
        createdAt: Date(),
        lastUsedAt: nil,
        isBackedUp: false,
        signingRecords: []
    )

    return SignMessageSheetView(key: mockKey)
        .environmentObject(KeyStore())
}
