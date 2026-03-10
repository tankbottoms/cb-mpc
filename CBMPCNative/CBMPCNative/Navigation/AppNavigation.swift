import SwiftUI

struct AppNavigation: View {
    @StateObject var keyStore: KeyStore = KeyStore()
    @SceneStorage("selectedTab") private var selectedTab = 0
    @State private var tabBarHidden = false

    #if os(iOS)
    var body: some View {
        iPhoneNavigationView()
            .environmentObject(keyStore)
    }

    @ViewBuilder
    func iPhoneNavigationView() -> some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0:
                    KeyDashboardView()
                case 1:
                    NetworkView()
                case 2:
                    SigningHistoryView()
                case 3:
                    TransactionsPlaceholderView()
                case 4:
                    NavigationStack {
                        DemoHubView()
                    }
                default:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)

            FloatingTabBar(selection: $selectedTab, isHidden: $tabBarHidden)
                .padding(.bottom, 4)
        }
        .ignoresSafeArea(.keyboard)
    }

    #elseif os(macOS)
    var body: some View {
        macOSNavigationView()
            .environmentObject(keyStore)
    }

    @ViewBuilder
    func macOSNavigationView() -> some View {
        NavigationSplitView {
            List(selection: $keyStore.selectedKeyId) {
                ForEach(keyStore.keys) { key in
                    NavigationLink(value: key.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.name)
                                .font(.system(.body, design: .monospaced))
                            Text(key.publicKeyDisplay)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Keys")
        } detail: {
            if let keyId = keyStore.selectedKeyId,
               let key = keyStore.keys.first(where: { $0.id == keyId }) {
                KeyDetailView(key: key)
            } else {
                Text("Select a key")
                    .foregroundColor(.secondary)
            }
        }
    }

    #else // iPadOS
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    var body: some View {
        iPadNavigationView()
            .environmentObject(keyStore)
    }

    @ViewBuilder
    func iPadNavigationView() -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $keyStore.selectedKeyId) {
                ForEach(keyStore.keys) { key in
                    NavigationLink(value: key.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.name)
                                .font(.system(.body, design: .monospaced))
                            Text(key.publicKeyDisplay)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Keys")
        } detail: {
            if let keyId = keyStore.selectedKeyId,
               let key = keyStore.keys.first(where: { $0.id == keyId }) {
                KeyDetailView(key: key)
            } else {
                Text("Select a key")
                    .foregroundColor(.secondary)
            }
        }
    }
    #endif
}

// MARK: - Placeholder Views

struct NetworkPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("Network")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Text("Device pairing, share distribution, and MPC server connections.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Text("COMING SOON")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Network")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

struct TransactionsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("Transactions")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Text("Contract interaction, ABI search, and transaction broadcasting.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Text("COMING SOON")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Transactions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

#Preview {
    AppNavigation()
}
