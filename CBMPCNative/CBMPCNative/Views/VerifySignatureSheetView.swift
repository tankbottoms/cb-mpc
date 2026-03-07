import SwiftUI
import CryptoKit

struct VerifySignatureSheetView: View {
    let key: ManagedKey
    @Environment(\.dismiss) var dismiss

    @State private var selectedRecord: SigningRecord?
    @State private var verifyResult: Bool?
    @State private var isVerifying = false
    @State private var verifyError: String?

    // Manual entry fields
    @State private var manualMessage = ""
    @State private var manualNonce = ""
    @State private var manualSignature = ""
    @State private var showManualEntry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !key.signingRecords.isEmpty && !showManualEntry {
                        Text("Select a record to verify")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)

                        ForEach(key.signingRecords.prefix(10)) { record in
                            Button(action: { verifyRecord(record) }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 9, design: .monospaced))
                                        Spacer()
                                        if selectedRecord?.id == record.id {
                                            if isVerifying {
                                                ProgressView()
                                                    .controlSize(.mini)
                                            } else if let result = verifyResult {
                                                Label(result ? "Valid" : "Invalid",
                                                      systemImage: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(result ? .green : .red)
                                            }
                                        }
                                    }

                                    Text("Hash: \(record.messageHash.prefix(40))...")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)

                                    Text("Sig: \(record.signature.prefix(40))...")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(8)
                                .background(.gray.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }

                        Divider()
                    }

                    // Manual verification
                    Button(action: { showManualEntry.toggle() }) {
                        HStack {
                            Text(showManualEntry ? "Hide Manual Entry" : "Manual Verification")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                            Spacer()
                            Image(systemName: showManualEntry ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.plain)

                    if showManualEntry {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Message")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                TextEditor(text: $manualMessage)
                                    .frame(height: 50)
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(4)
                                    .background(.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nonce")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                TextField("Nonce (optional)", text: $manualNonce)
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(6)
                                    .background(.gray.opacity(0.1))
                                    .cornerRadius(4)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Signature (hex)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                TextEditor(text: $manualSignature)
                                    .frame(height: 50)
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(4)
                                    .background(.gray.opacity(0.1))
                                    .cornerRadius(4)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }

                            Button(action: verifyManual) {
                                if isVerifying {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.mini)
                                        Text("Verifying...")
                                    }
                                } else {
                                    Label("Verify", systemImage: "checkmark.shield")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.borderedProminent)
                            .disabled(isVerifying || manualMessage.isEmpty || manualSignature.isEmpty)
                        }
                    }

                    // Result display
                    if let error = verifyError {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.red)
                        }
                        .padding(6)
                        .background(.red.opacity(0.1))
                        .cornerRadius(4)
                    }

                    if let result = verifyResult, !isVerifying {
                        HStack {
                            Image(systemName: result ? "checkmark.shield.fill" : "xmark.shield.fill")
                                .foregroundColor(result ? .green : .red)
                            Text(result ? "Signature is valid" : "Signature is invalid")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(result ? .green : .red)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((result ? Color.green : Color.red).opacity(0.1))
                        .cornerRadius(4)
                    }
                }
                .padding(12)
            }
            .navigationTitle("Verify Signature")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func verifyRecord(_ record: SigningRecord) {
        selectedRecord = record
        isVerifying = true
        verifyResult = nil
        verifyError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            guard let pubKeyData = CBMPCCryptoEngine.parseSignatureHex(key.publicKey) else {
                DispatchQueue.main.async {
                    verifyError = "Invalid public key hex"
                    isVerifying = false
                }
                return
            }
            guard let hashData = CBMPCCryptoEngine.parseSignatureHex(record.messageHash) else {
                DispatchQueue.main.async {
                    verifyError = "Invalid message hash hex"
                    isVerifying = false
                }
                return
            }
            guard let sigData = CBMPCCryptoEngine.parseSignatureHex(record.signature) else {
                DispatchQueue.main.async {
                    verifyError = "Invalid signature hex"
                    isVerifying = false
                }
                return
            }

            let result = CBMPCCryptoEngine.verifySignature(
                curveCode: Int(key.curveCode),
                publicKey: pubKeyData,
                messageHash: hashData,
                derSignature: sigData
            )

            DispatchQueue.main.async {
                verifyResult = result
                isVerifying = false
            }
        }
    }

    private func verifyManual() {
        isVerifying = true
        verifyResult = nil
        verifyError = nil
        selectedRecord = nil

        DispatchQueue.global(qos: .userInitiated).async {
            guard let pubKeyData = CBMPCCryptoEngine.parseSignatureHex(key.publicKey) else {
                DispatchQueue.main.async {
                    verifyError = "Invalid public key hex"
                    isVerifying = false
                }
                return
            }

            // Build message with nonce (same as signing flow)
            let fullMessage = manualNonce.isEmpty ? manualMessage : "\(manualMessage)|\(manualNonce)"
            let messageData = fullMessage.data(using: .utf8) ?? Data()
            let hashData = sha256(messageData)

            guard let sigData = CBMPCCryptoEngine.parseSignatureHex(
                manualSignature.trimmingCharacters(in: .whitespacesAndNewlines)
            ) else {
                DispatchQueue.main.async {
                    verifyError = "Invalid signature hex"
                    isVerifying = false
                }
                return
            }

            let result = CBMPCCryptoEngine.verifySignature(
                curveCode: Int(key.curveCode),
                publicKey: pubKeyData,
                messageHash: hashData,
                derSignature: sigData
            )

            DispatchQueue.main.async {
                verifyResult = result
                isVerifying = false
            }
        }
    }
}
