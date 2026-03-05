import SwiftUI

struct AppNavigation: View {
    @StateObject var keyStore: KeyStore = KeyStore()
    @State private var selectedTab = 0

    #if os(iOS)
    var body: some View {
        iPhoneNavigationView()
            .environmentObject(keyStore)
    }

    private let tabBarTotalHeight: CGFloat = 96

    @ViewBuilder
    func iPhoneNavigationView() -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Group {
                    switch selectedTab {
                    case 0:
                        KeyDashboardView()
                    case 1:
                        SigningHistoryView()
                    case 2:
                        Text("QR Scanner")
                            .font(.system(.title3, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    default:
                        SettingsView()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height - tabBarTotalHeight)
                .clipped()

                FloatingTabBar(selection: $selectedTab)
                    .padding(.bottom, 28)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
