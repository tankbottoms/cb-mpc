import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var keyStore: KeyStore
    @State private var serverUrl = "https://api.cbmpc.example.com"
    @State private var useMockServer = false
    @State private var useICloudSync = true
    @AppStorage("signingServerURL") private var signingServerURL = ""

    var body: some View {
        NavigationStack {
            List {
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
                    TextField("Signing Server URL", text: $signingServerURL, prompt: Text("https://server/submit"))
                        .font(.system(.caption, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }

                Section(header: Text("Sync & Backup")) {
                    Toggle("iCloud Keychain Sync", isOn: $useICloudSync)
                        .font(.system(size: 14))

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
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
                            .font(.system(.caption, design: .monospaced))
                    }

                    HStack {
                        Text("Build")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
