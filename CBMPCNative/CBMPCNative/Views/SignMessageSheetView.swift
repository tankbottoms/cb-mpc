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

    @State private var message = ""
    @State private var nonce = UUID().uuidString
    @State private var isSigning = false
    @State private var signature: String?
    @AppStorage("signingServerURL") private var signingServerURL = "https://server/submit"
    @State private var showServerSubmitSheet = false
    @State private var serverSubmitInProgress = false
    @State private var serverSubmitError: String?
    @State private var signError: String?
    @State private var signStartTime: Date?
    @State private var signDuration: TimeInterval?
    @State private var transportInfo: String?
    @StateObject private var ceremonyCoordinator = CeremonyCoordinator()

    var messageHash: String {
        let data = message.data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
              ScrollView {
                VStack(spacing: 10) {
                    // Message Input
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Message")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)

                        TextEditor(text: $message)
                            .frame(height: 70)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(6)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)
                            .border(Color.gray.opacity(0.3), width: 0.5)

                        // SHA-256 hash directly under message
                        Text("SHA-256")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)

                        Text(messageHash)
                            .font(.system(size: 9, design: .monospaced))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .foregroundColor(.secondary)
                    }

                    // Nonce Field
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Nonce")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: { nonce = UUID().uuidString }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                        }

                        Text(nonce.uppercased())
                            .font(.system(size: 9, design: .monospaced))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)
                            .textSelection(.enabled)

                        Text("A unique random value appended to the message before signing. Prevents replay attacks by ensuring each signature is bound to a single-use token. Generated using UUID v4 (122 bits of randomness).")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(3)
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

                            HStack(alignment: .top, spacing: 4) {
                                Text(sig)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(3)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                Button(action: { copyToClipboard(sig) }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)

                            // Signing diagnostics
                            VStack(alignment: .leading, spacing: 3) {
                                if let info = transportInfo {
                                    HStack(spacing: 4) {
                                        Text("Transport")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(info)
                                    }
                                }
                                if let duration = signDuration {
                                    HStack(spacing: 4) {
                                        Text("Duration")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(String(format: "%.2fs", duration))
                                    }
                                }
                                HStack(spacing: 4) {
                                    Text("Payload")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    let inputBytes = (message.data(using: .utf8)?.count ?? 0) + nonce.count + 1
                                    Text("\(inputBytes) bytes -> \(sig.count / 2) bytes")
                                }
                            }
                            .font(.system(size: 8, design: .monospaced))
                            .padding(6)
                            .background(.blue.opacity(0.05))
                            .cornerRadius(4)
                        }
                    }
                }
                .padding(12)
              }

              // Sign Button — always visible above keyboard
              VStack {
                if signature == nil {
                    // Show transport origin for non-local keys
                    if TransportOrigin.load(for: key.id) != .local {
                        HStack(spacing: 6) {
                            let origin = TransportOrigin.load(for: key.id)
                            Image(systemName: origin == .server ? "server.rack" : "iphone.gen2")
                                .font(.system(size: 10))
                            if isLocallyDerived {
                                Text("Locally-derived from \(origin == .server ? "server" : "peer") parent")
                                    .font(.system(size: 9, design: .monospaced))
                            } else {
                                Text(origin == .server ? "Server-backed signing" : "Peer-backed signing")
                                    .font(.system(size: 9, design: .monospaced))
                            }
                        }
                        .foregroundColor(.blue)
                        .padding(.bottom, 4)
                    }

                    Button(action: signMessage) {
                        if isSigning {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(signingProgressLabel)
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
              .padding(.horizontal, 12)
              .padding(.bottom, 8)
            }
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
            #if os(iOS)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            #endif
            .alert("Error", isPresented: Binding(get: { signError != nil }, set: { if !$0 { signError = nil } })) {
                Button("OK") { signError = nil }
            } message: {
                Text(signError ?? "")
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

    /// Check if key has both shares on device (locally-derived from server/peer parent)
    private var isLocallyDerived: Bool {
        UserDefaults.standard.bool(forKey: "key_\(key.id.uuidString)_localDerived")
    }

    private var signingProgressLabel: String {
        if isLocallyDerived || TransportOrigin.load(for: key.id) == .local {
            return "Signing..."
        } else {
            return "Signing with server..."
        }
    }

    private func signMessage() {
        // HD master keys can't sign directly — must derive a child key first
        if key.keyType == .hdMaster {
            signError = "HD master keys cannot sign directly. Derive a child key first (e.g., m/44'/60'/0'/0/0) and sign with that."
            return
        }

        isSigning = true
        signError = nil
        signStartTime = Date()

        let messageWithNonce = "\(message)|\(nonce)"
        let origin = TransportOrigin.load(for: key.id)

        // Set transport info — accurately reflects actual signing path
        switch origin {
        case .local:
            transportInfo = "Local (2 shares on device)"
        case .server:
            if isLocallyDerived {
                // HD-child derived from server parent — both shares on device
                if let serverURL = TransportOrigin.coSignerRef(for: key.id) {
                    let host = URL(string: serverURL)?.host ?? serverURL
                    transportInfo = "Local (derived from server: \(host))"
                } else {
                    transportInfo = "Local (derived from server parent)"
                }
            } else {
                if let serverURL = TransportOrigin.coSignerRef(for: key.id) {
                    let host = URL(string: serverURL)?.host ?? serverURL
                    transportInfo = "Server (\(host))"
                } else {
                    transportInfo = "Server"
                }
            }
        case .peer:
            if isLocallyDerived {
                transportInfo = "Local (derived from peer parent)"
            } else if let deviceIdStr = TransportOrigin.coSignerRef(for: key.id),
               let deviceUUID = UUID(uuidString: deviceIdStr),
               let device = PairingManager.shared.pairedDevices.first(where: { $0.id == deviceUUID }) {
                transportInfo = "Peer (\(device.name))"
            } else {
                transportInfo = "Peer"
            }
        }

        // Route: locally-derived keys always sign locally regardless of origin badge
        if isLocallyDerived || origin == .local {
            signLocal(messageWithNonce: messageWithNonce)
        } else {
            signAsync(messageWithNonce: messageWithNonce)
        }
    }

    private func signLocal(messageWithNonce: String) {
        let keyId = key.id
        let curveCode = Int(key.curveCode)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let keyData = UserDefaults.standard.data(forKey: "key_\(keyId.uuidString)") else {
                    throw CBMPCError.invalidKeyData
                }
                let engine = CBMPCCryptoEngine()
                let messageData = messageWithNonce.data(using: .utf8) ?? Data()
                let messageHash = sha256(messageData)
                let sigData = try engine.signMessage(messageHash, keyData: keyData, curveCode: curveCode)
                let sigHex = sigData.map { String(format: "%02X", $0) }.joined()
                let hashHex = messageHash.map { String(format: "%02X", $0) }.joined()
                DispatchQueue.main.async {
                    self.handleSigningSuccess(sigHex: sigHex, hashHex: hashHex)
                }
            } catch {
                DispatchQueue.main.async {
                    self.signError = "Signing failed: \(error.localizedDescription)"
                    self.isSigning = false
                }
            }
        }
    }

    private func signAsync(messageWithNonce: String) {
        let origin = TransportOrigin.load(for: key.id)
        Task { @MainActor in
            do {
                let ceremony = try ceremonyCoordinator.createSigningCeremony(
                    participantMode: origin == .server ? .server : .device,
                    localPartyId: 0,
                    messageHash: messageWithNonce.data(using: .utf8) ?? Data()
                )
                try ceremonyCoordinator.updateState(ceremonyId: ceremony.id, newState: .committed)

                let sigHex = try await keyStore.signMessageAsync(messageWithNonce, with: key)
                let messageData = messageWithNonce.data(using: .utf8) ?? Data()
                let messageHash = sha256(messageData)
                let hashHex = messageHash.map { String(format: "%02X", $0) }.joined()

                try ceremonyCoordinator.updateState(ceremonyId: ceremony.id, newState: .signed)
                try ceremonyCoordinator.completeCeremony(
                    ceremonyId: ceremony.id,
                    publicKey: key.publicKey,
                    shareId: ""
                )

                self.handleSigningSuccess(sigHex: sigHex, hashHex: hashHex)
            } catch {
                if let ceremony = ceremonyCoordinator.activeCeremony {
                    try? ceremonyCoordinator.failCeremony(
                        ceremonyId: ceremony.id,
                        error: error.localizedDescription
                    )
                }
                self.signError = "Signing failed: \(error.localizedDescription)"
                self.isSigning = false
            }
        }
    }

    private func handleSigningSuccess(sigHex: String, hashHex: String) {
        if let start = signStartTime {
            self.signDuration = Date().timeIntervalSince(start)
        }
        self.signature = sigHex
        self.isSigning = false

        #if os(iOS)
        UIPasteboard.general.string = sigHex
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        #endif

        // Build transport details string for signing record
        var transportDetail = transportInfo ?? "Local"
        if let duration = signDuration {
            transportDetail += " | \(String(format: "%.2f", duration))s"
        }
        let origin = TransportOrigin.load(for: key.id)
        if isLocallyDerived && origin != .local {
            transportDetail += " | 2 shares on device (parent: \(origin.rawValue))"
        } else {
            transportDetail += " | \(origin.shareDescription)"
        }

        let record = SigningRecord(
            id: UUID(),
            messageHash: hashHex,
            signature: sigHex,
            timestamp: Date(),
            verified: true,
            transportInfo: transportDetail
        )
        self.keyStore.addSigningRecord(record, to: self.key.id)
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
