import SwiftUI

struct AppNavigation: View {
    @StateObject var keyStore: KeyStore = KeyStore()
    @SceneStorage("selectedTab") private var selectedTab = 0
    @AppStorage("hasSeenVaultWelcome") private var hasSeenVaultWelcome = false
    @State private var tabBarHidden = false

    #if os(iOS)
    var body: some View {
        Group {
            if !hasSeenVaultWelcome && keyStore.keys.isEmpty {
                WelcomeView(hasCompletedOnboarding: $hasSeenVaultWelcome)
                    .environmentObject(keyStore)
            } else {
                iPhoneNavigationView()
                    .environmentObject(keyStore)
            }
        }
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
                    TransactionsTabView()
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
        .onReceive(NotificationCenter.default.publisher(for: .switchToSettingsTab)) { _ in
            selectedTab = 5
        }
    }

    #elseif os(macOS)
    var body: some View {
        macOSNavigationView()
            .environmentObject(keyStore)
    }

    enum MacSection: String, CaseIterable, Identifiable {
        case keys = "Keys"
        case network = "Network"
        case history = "Signing History"
        case transactions = "Transactions"
        case demos = "Demos"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .keys: return "key.fill"
            case .network: return "antenna.radiowaves.left.and.right"
            case .history: return "clock.fill"
            case .transactions: return "arrow.left.arrow.right"
            case .demos: return "flask.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    @State private var selectedSection: MacSection = .keys
    @State private var showCreateKeySheet = false

    @ViewBuilder
    func macOSNavigationView() -> some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(MacSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            .navigationTitle("CB-MPC")
            .listStyle(.sidebar)
        } detail: {
            switch selectedSection {
            case .keys:
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
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button(action: { showCreateKeySheet = true }) {
                                Label("Create Key", systemImage: "plus")
                            }
                        }
                    }
                    .sheet(isPresented: $showCreateKeySheet) {
                        CreateKeySheetView()
                            .environmentObject(keyStore)
                            .frame(minWidth: 500, minHeight: 400)
                    }
                } detail: {
                    if let keyId = keyStore.selectedKeyId,
                       let key = keyStore.keys.first(where: { $0.id == keyId }) {
                        KeyDetailView(key: key)
                    } else {
                        Text("Select a key")
                            .foregroundColor(.secondary)
                    }
                }
            case .network:
                NetworkView()
            case .history:
                SigningHistoryView()
            case .transactions:
                TransactionsTabView()
            case .demos:
                NavigationStack {
                    DemoHubView()
                }
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 800, minHeight: 500)
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
            PlaceholderScreen(
                icon: "arrow.left.arrow.right",
                title: "Transactions",
                description: "Contract interaction, ABI search, and transaction broadcasting."
            )
            .navigationTitle("Transactions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let switchToSettingsTab = Notification.Name("switchToSettingsTab")
}

#Preview {
    AppNavigation()
}
