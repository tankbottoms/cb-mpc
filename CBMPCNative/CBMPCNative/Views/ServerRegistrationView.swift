import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ServerRegistrationView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var pairingManager = PairingManager.shared

    @State private var serverURL = ""
    @State private var serverName = ""
    @State private var isConnecting = false
    @State private var connectionResult: ConnectionResult?
    @State private var errorMessage: String?

    enum ConnectionResult {
        case success(version: String?)
        case failure(message: String)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MPC SERVER")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text("Register an MPC server to hold one key share. The server participates in threshold signing but cannot sign alone.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.05))
                .cornerRadius(6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("SERVER NAME")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    TextField("My MPC Server", text: $serverName)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(10)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("SERVER URL")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    TextField("https://api.cbmpc.example.com", text: $serverURL)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(10)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit { testConnection() }
                }

                // Connection test result
                if isConnecting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Connecting...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.gray.opacity(0.05))
                    .cornerRadius(6)
                }

                if let result = connectionResult {
                    switch result {
                    case .success(let version):
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connection successful")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.green)
                                if let v = version {
                                    Text("Server version: \(v)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.green.opacity(0.05))
                        .cornerRadius(6)

                    case .failure(let message):
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(message)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.red)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.05))
                        .cornerRadius(6)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("SECURITY")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("The server holds one key share and participates in threshold signing protocols. It cannot sign transactions alone -- a quorum of parties is always required. Communication uses HTTPS with certificate pinning.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(.gray.opacity(0.05))
                .cornerRadius(6)

                Spacer()

                VStack(spacing: 8) {
                    Button(action: testConnection) {
                        Text("Test Connection")
                            .font(.system(size: 14, design: .monospaced))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)

                    Button(action: registerServer) {
                        Text("Register Server")
                            .font(.system(size: 14, design: .monospaced))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
                }
            }
            .padding(16)
            .navigationTitle("Add Server")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }

    private func testConnection() {
        let url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        isConnecting = true
        connectionResult = nil

        let server = MPCServer(
            id: UUID(),
            name: serverName.isEmpty ? "MPC Server" : serverName,
            url: url,
            registeredAt: Date(),
            isOnline: false,
            shareCount: 0
        )

        pairingManager.pingServer(server) { success, version in
            isConnecting = false
            if success {
                connectionResult = .success(version: version)
            } else {
                connectionResult = .failure(message: version ?? "Connection failed")
            }
        }
    }

    private func registerServer() {
        let url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        var apiVersion: String?
        if case .success(let v) = connectionResult {
            apiVersion = v
        }

        let server = MPCServer(
            id: UUID(),
            name: serverName.isEmpty ? "MPC Server" : serverName,
            url: url,
            registeredAt: Date(),
            lastSeenAt: Date(),
            isOnline: true,
            shareCount: 0,
            apiVersion: apiVersion
        )

        pairingManager.addServer(server)

        #if os(iOS)
        let impact = UINotificationFeedbackGenerator()
        impact.notificationOccurred(.success)
        #endif

        dismiss()
    }
}
