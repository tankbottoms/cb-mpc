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

                    Toggle("Use Mock Server", isOn: $useMockServer)
                }

                Section(header: Text("Signing Server")) {
                    TextField("Signing Server URL", text: $signingServerURL, prompt: Text("https://server/submit"))
                        .font(.system(.caption, design: .monospaced))
                        .textInputAutocapitalization(.never)
                }

                Section(header: Text("Sync & Backup")) {
                    Toggle("iCloud Keychain Sync", isOn: $useICloudSync)

                    Button(action: {
                        keyStore.seedDemoData()
                    }) {
                        Label("Reset Demo Data", systemImage: "arrow.counterclockwise")
                    }
                }

                Section(header: Text("App Info")) {
                    HStack {
                        Text("Version")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("1.0.0")
                            .font(.system(.caption, design: .monospaced))
                    }

                    HStack {
                        Text("Build")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("1")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
