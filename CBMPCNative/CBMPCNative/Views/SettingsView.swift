import SwiftUI
import CryptoKit

struct SettingsView: View {
    @EnvironmentObject var keyStore: KeyStore
    @AppStorage("serverUrl") private var serverUrl = "https://api.cbmpc.atsignhandle.xyz"
    @State private var useMockServer = false
    @State private var useICloudSync = true
    @AppStorage("signingServerURL") private var signingServerURL = "https://signing.cbmpc.atsignhandle.xyz/submit"
    @AppStorage("instructionLevel") private var instructionLevel = "verbose"
    @AppStorage("ethereumRPC") private var ethereumRPC = "hoodi"
    @AppStorage("infuraAPIKey") private var infuraAPIKey = "65980db64d52417abbda13b49e356d97"
    @AppStorage("exportFormat") private var exportFormat = "keystoreJSON"
    @AppStorage("useFaceID") private var useFaceID = false
    @AppStorage("keystorePasswordHash") private var keystorePasswordHash = ""
    @AppStorage("keystorePasswordSetDate") private var keystorePasswordSetDate = ""
    @AppStorage("hdChildNamingUseSelf") private var hdChildNamingUseSelf = false

    @State private var showPasswordSheet = false

    private var hasNonDerivedKeys: Bool {
        keyStore.keys.contains { $0.keyType != .hdChild }
    }

    private var rpcURL: String {
        switch ethereumRPC {
        case "mainnet":
            return "https://mainnet.infura.io/v3/\(infuraAPIKey)"
        case "sepolia":
            return "https://sepolia.infura.io/v3/\(infuraAPIKey)"
        default:
            return "https://hoodi.infura.io/v3/\(infuraAPIKey)"
        }
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (build \(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Ethereum RPC")) {
                    Picker("Network", selection: $ethereumRPC) {
                        Text("Hoodi (testnet)").tag("hoodi")
                        Text("Sepolia (testnet)").tag("sepolia")
                        Text("Mainnet").tag("mainnet")
                    }
                    .font(.system(size: 14))

                    HStack {
                        Text("RPC URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(rpcURL)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Infura API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("API Key", text: $infuraAPIKey)
                            .font(.system(.caption, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Text("Chain ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(ethereumRPC == "mainnet" ? "1" : ethereumRPC == "sepolia" ? "11155111" : "560048")
                            .font(.system(.caption, design: .monospaced))
                    }
                }

                Section(header: Text("Server Configuration")) {
                    TextField("Server URL", text: $serverUrl)
                        .font(.system(.caption, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)

                    Toggle("Use Mock Server", isOn: $useMockServer)
                        .font(.system(size: 14))
                }

                Section(header: Text("Signing Server")) {
                    TextField("Signing Server URL", text: $signingServerURL, prompt: Text("https://signing.cbmpc.atsignhandle.xyz/submit"))
                        .font(.system(.caption, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }

                Section(header: Text("Export Format")) {
                    Picker("Format", selection: $exportFormat) {
                        Text("Keystore JSON").tag("keystoreJSON")
                        Text("Private Key").tag("privateKey")
                        Text("Seed Phrase").tag("seedPhrase")
                    }
                    .font(.system(size: 14))
                }

                Section(header: Text("Security")) {
                    if hasNonDerivedKeys {
                        Toggle("Face ID", isOn: $useFaceID)
                            .font(.system(size: 14))
                    } else {
                        HStack {
                            Text("Face ID")
                                .font(.system(size: 14))
                            Spacer()
                            Text("No root keys")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Password toggle -- opens sheet to set/change
                    HStack {
                        Text("Password")
                            .font(.system(size: 14))
                        Spacer()
                        if !keystorePasswordHash.isEmpty {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Enabled")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.green)
                                if !keystorePasswordSetDate.isEmpty {
                                    Text("Set \(keystorePasswordSetDate)")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Text("Disabled")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showPasswordSheet = true
                    }
                }

                Section(header: Text("Key Naming")) {
                    Toggle("HD-CHILD uses own address", isOn: $hdChildNamingUseSelf)
                        .font(.system(size: 14))

                    Text(hdChildNamingUseSelf
                        ? "HD-CHILD keys named using their own 0x address"
                        : "HD-CHILD keys named using the HD-MASTER's 0x address")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Display")) {
                    Picker("Instruction Level", selection: $instructionLevel) {
                        Text("Off").tag("off")
                        Text("Minimal").tag("minimal")
                        Text("Verbose").tag("verbose")
                    }
                    .font(.system(size: 14))
                }

                Section(header: Text("Sync & Backup")) {
                    Toggle("iCloud Keychain Sync", isOn: $useICloudSync)
                        .font(.system(size: 14))

                    Button(action: {
                        keyStore.backupToICloud()
                    }) {
                        Label("Backup to iCloud Now", systemImage: "icloud.and.arrow.up")
                            .font(.system(size: 12))
                    }

                    Button(action: {
                        keyStore.seedDemoData()
                    }) {
                        if keyStore.isSeedingDemoData {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Generating keys...")
                                    .font(.system(size: 12))
                            }
                        } else {
                            Label("Reset Demo Data", systemImage: "arrow.counterclockwise")
                        }
                    }
                    .disabled(keyStore.isSeedingDemoData)
                }

                Section(header: Text("App Info")) {
                    HStack {
                        Text("Version")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(versionString)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
            .sheet(isPresented: $showPasswordSheet) {
                PasswordSetupSheetView(
                    keystorePasswordHash: $keystorePasswordHash,
                    keystorePasswordSetDate: $keystorePasswordSetDate
                )
                .presentationDetents([.medium])
            }
        }
    }
}

// MARK: - Password Setup Sheet

struct PasswordSetupSheetView: View {
    @Binding var keystorePasswordHash: String
    @Binding var keystorePasswordSetDate: String
    @Environment(\.dismiss) var dismiss

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordError: String?
    @State private var passwordSaved = false

    private var passwordsMatch: Bool {
        !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword == confirmPassword
    }

    private var passwordsMismatch: Bool {
        !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword != confirmPassword
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Instructions
                VStack(alignment: .leading, spacing: 6) {
                    Text("APP LOCK PASSWORD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))

                    Text("Set a password to lock the app on launch. This password is required when Face ID is unavailable or disabled. The password hash is stored locally using SHA-256.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(.blue.opacity(0.05))
                .cornerRadius(6)

                VStack(alignment: .leading, spacing: 8) {
                    SecureField("New Password", text: $newPassword)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Confirm Password", text: $confirmPassword)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if passwordsMismatch {
                        Text("Passwords do not match")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.red)
                    } else if passwordsMatch {
                        Text("Passwords match")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    if let err = passwordError {
                        Text(err)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.red)
                    }

                    if passwordSaved {
                        Text("Password saved successfully")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                VStack(spacing: 8) {
                    Button(action: savePassword) {
                        Text(keystorePasswordHash.isEmpty ? "Set Password" : "Change Password")
                            .font(.system(size: 14, design: .monospaced))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!passwordsMatch)

                    if !keystorePasswordHash.isEmpty {
                        Button(action: {
                            keystorePasswordHash = ""
                            keystorePasswordSetDate = ""
                            dismiss()
                        }) {
                            Text("Remove Password")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(16)
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func savePassword() {
        passwordError = nil
        passwordSaved = false

        guard newPassword == confirmPassword else {
            passwordError = "Passwords do not match"
            return
        }
        guard newPassword.count >= 4 else {
            passwordError = "Minimum 4 characters"
            return
        }

        let hash = SHA256.hash(data: Data(newPassword.utf8))
        keystorePasswordHash = hash.map { String(format: "%02x", $0) }.joined()
        keystorePasswordSetDate = AppDateFormat.string(from: Date())
        newPassword = ""
        confirmPassword = ""
        passwordSaved = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
        }
    }
}

#Preview {
    SettingsView()
}
