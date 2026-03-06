import SwiftUI

struct AppNavigation: View {
    @StateObject var keyStore: KeyStore = KeyStore()
    @State private var selectedTab = 2
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
                    SigningHistoryView()
                case 2:
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

#Preview {
    AppNavigation()
}
