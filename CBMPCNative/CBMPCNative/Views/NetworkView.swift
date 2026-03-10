import SwiftUI
import Security
#if os(iOS)
import UIKit
#endif

struct NetworkView: View {
    @EnvironmentObject var keyStore: KeyStore

    @ObservedObject var pairingManager = PairingManager.shared
    @State private var nodes: [NetworkNode] = []
    @State private var isRefreshing = false
    @State private var showPairingSheet = false
    @State private var showServerSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("NODES"), footer:
                    Text("All locations where key shares and keystore data are stored. Tap a node to see details.")
                        .font(.system(size: 10, design: .monospaced))
                ) {
                    ForEach(nodes) { node in
                        NavigationLink(destination: NodeDetailView(node: node, keyStore: keyStore)) {
                            NodeRow(node: node)
                        }
                    }
                }

                if !nodes.isEmpty {
                    Section(header: Text("KEY DISTRIBUTION")) {
                        ForEach(keyStore.keys) { key in
                            KeyDistributionRow(key: key, nodes: nodes)
                        }

                        if keyStore.keys.isEmpty {
                            Text("No keys created yet")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Button(action: { showPairingSheet = true }) {
                        Label("Pair Device", systemImage: "qrcode.viewfinder")
                            .font(.system(size: 13, design: .monospaced))
                    }

                    Button(action: { showServerSheet = true }) {
                        Label("Add Server", systemImage: "server.rack")
                            .font(.system(size: 13, design: .monospaced))
                    }
                }

                // Bottom spacer for floating tab bar
                Section {
                    EmptyView()
                }
                .listRowBackground(Color.clear)
                .frame(height: 80)
            }
            .navigationTitle("Network")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { refreshNodes() }) {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                        }
                    }
                }
            }
            .onAppear { refreshNodes() }
            .sheet(isPresented: $showPairingSheet) {
                DevicePairingView()
                    .onDisappear { refreshNodes() }
            }
            .sheet(isPresented: $showServerSheet) {
                ServerRegistrationView()
                    .onDisappear { refreshNodes() }
            }
        }
    }

    private func refreshNodes() {
        isRefreshing = true
        var allNodes: [NetworkNode] = []

        allNodes.append(buildThisDeviceNode())
        allNodes.append(buildICloudNode())

        // Add paired devices
        for device in pairingManager.pairedDevices {
            allNodes.append(NetworkNode(
                id: device.id.uuidString,
                name: device.name,
                icon: "iphone",
                nodeType: .pairedDevice,
                status: device.isOnline ? .active : .offline,
                shareCount: device.shareCount,
                keychainItems: 0,
                keychainBytes: 0,
                userDefaultsEntries: 0,
                userDefaultsBytes: 0,
                deviceModel: device.deviceModel,
                lastSeen: device.lastSeenAt
            ))
        }

        // Add servers
        for server in pairingManager.servers {
            allNodes.append(NetworkNode(
                id: server.id.uuidString,
                name: server.name,
                icon: "server.rack",
                nodeType: .server,
                status: server.isOnline ? .active : .offline,
                shareCount: server.shareCount,
                keychainItems: 0,
                keychainBytes: 0,
                userDefaultsEntries: 0,
                userDefaultsBytes: 0,
                deviceModel: server.url,
                lastSeen: server.lastSeenAt
            ))
        }

        nodes = allNodes
        isRefreshing = false
    }

    // MARK: - Node Builders

    private func buildThisDeviceNode() -> NetworkNode {
        // Count UserDefaults key entries
        let defaults = UserDefaults.standard
        let keyPrefix = "key_"
        let udKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(keyPrefix) }
        var udBytes = 0
        for k in udKeys {
            if let data = defaults.data(forKey: k) { udBytes += data.count }
        }

        // Count Device Keychain items
        let kcQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "xyz.atsignhandle.cb-mpc.keystore",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var kcResult: AnyObject?
        let kcStatus = SecItemCopyMatching(kcQuery as CFDictionary, &kcResult)
        var kcCount = 0
        var kcBytes = 0
        if kcStatus == errSecSuccess, let items = kcResult as? [Data] {
            kcCount = items.count
            kcBytes = items.reduce(0) { $0 + $1.count }
        }

        let deviceName: String = {
            #if os(iOS)
            return UIDevice.current.name
            #else
            return Host.current().localizedName ?? "This Mac"
            #endif
        }()

        let deviceModel: String = {
            #if os(iOS)
            return UIDevice.current.model
            #else
            return "Mac"
            #endif
        }()

        return NetworkNode(
            id: "this-device",
            name: deviceName,
            icon: "iphone",
            nodeType: .thisDevice,
            status: .active,
            shareCount: keyStore.keys.count,
            keychainItems: kcCount,
            keychainBytes: kcBytes,
            userDefaultsEntries: udKeys.count,
            userDefaultsBytes: udBytes,
            deviceModel: deviceModel,
            lastSeen: Date()
        )
    }

    private func buildICloudNode() -> NetworkNode {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "xyz.atsignhandle.cb-mpc.keychain-sync",
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        var count = 0
        var bytes = 0
        if status == errSecSuccess, let items = result as? [Data] {
            count = items.count
            bytes = items.reduce(0) { $0 + $1.count }
        }

        return NetworkNode(
            id: "icloud",
            name: "iCloud Keychain",
            icon: "icloud.fill",
            nodeType: .icloud,
            status: count > 0 ? .synced : .empty,
            shareCount: count,
            keychainItems: count,
            keychainBytes: bytes,
            userDefaultsEntries: 0,
            userDefaultsBytes: 0,
            deviceModel: nil,
            lastSeen: count > 0 ? Date() : nil
        )
    }
}

// MARK: - Data Model

struct NetworkNode: Identifiable {
    let id: String
    let name: String
    let icon: String
    let nodeType: NodeType
    let status: NodeStatus
    let shareCount: Int
    let keychainItems: Int
    let keychainBytes: Int
    let userDefaultsEntries: Int
    let userDefaultsBytes: Int
    let deviceModel: String?
    let lastSeen: Date?

    var totalBytes: Int { keychainBytes + userDefaultsBytes }

    var totalBytesDisplay: String {
        let kb = Double(totalBytes) / 1024.0
        if kb < 1 { return "\(totalBytes) B" }
        return String(format: "%.1f KB", kb)
    }

    enum NodeType {
        case thisDevice, icloud, pairedDevice, server
    }

    enum NodeStatus: String {
        case active = "Active"
        case synced = "Synced"
        case offline = "Offline"
        case empty = "Empty"

        var color: Color {
            switch self {
            case .active: return .green
            case .synced: return .blue
            case .offline: return .orange
            case .empty: return .gray
            }
        }
    }
}

// MARK: - Node Row

struct NodeRow: View {
    let node: NetworkNode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.icon)
                .font(.system(size: 20))
                .foregroundColor(node.status.color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    Circle()
                        .fill(node.status.color)
                        .frame(width: 6, height: 6)
                }

                HStack(spacing: 8) {
                    Text(node.status.rawValue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(node.status.color)

                    if node.shareCount > 0 {
                        Text("\(node.shareCount) key\(node.shareCount == 1 ? "" : "s")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if node.totalBytes > 0 {
                        Text(node.totalBytesDisplay)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Node Detail

struct NodeDetailView: View {
    let node: NetworkNode
    let keyStore: KeyStore

    var body: some View {
        List {
            Section(header: Text("NODE INFO")) {
                infoRow("Name", node.name)
                infoRow("Type", nodeTypeLabel)
                infoRow("Status", node.status.rawValue)
                if let model = node.deviceModel {
                    infoRow("Device", model)
                }
                if let seen = node.lastSeen {
                    infoRow("Last Seen", formatDate(seen))
                }
            }

            Section(header: Text("STORAGE")) {
                if node.nodeType == .thisDevice {
                    infoRow("Device Keychain", "\(node.keychainItems) item\(node.keychainItems == 1 ? "" : "s") (\(formatBytes(node.keychainBytes)))")
                    infoRow("UserDefaults", "\(node.userDefaultsEntries) entr\(node.userDefaultsEntries == 1 ? "y" : "ies") (\(formatBytes(node.userDefaultsBytes)))")
                    infoRow("Total", node.totalBytesDisplay)
                } else if node.nodeType == .icloud {
                    infoRow("Synced Items", "\(node.keychainItems) item\(node.keychainItems == 1 ? "" : "s")")
                    infoRow("Size", formatBytes(node.keychainBytes))
                }
            }

            if node.shareCount > 0 {
                Section(header: Text("KEYS ON THIS NODE")) {
                    if node.nodeType == .thisDevice {
                        ForEach(keyStore.keys) { key in
                            KeyOnNodeRow(key: key)
                        }
                    } else if node.nodeType == .icloud {
                        // Show keys that have been synced to iCloud
                        ForEach(keyStore.keys.filter { keySyncedToICloud($0) }) { key in
                            KeyOnNodeRow(key: key)
                        }
                        if keyStore.keys.filter({ keySyncedToICloud($0) }).isEmpty {
                            Text("No keys synced to iCloud Keychain")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if node.nodeType == .thisDevice {
                Section(header: Text("SECURITY")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Device Keychain")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text("AES-256 encrypted at rest by iOS data protection. Tied to device hardware UID. Never leaves this device. Requires unlock (passcode/Face ID).")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("UserDefaults")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text("Local app storage for key share data. Protected by iOS app sandbox and device-level encryption (NSFileProtectionComplete).")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            } else if node.nodeType == .icloud {
                Section(header: Text("SECURITY")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("iCloud Keychain")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text("Apple end-to-end encrypted. Syncs across devices signed into same Apple ID. Protected by device passcode + Apple ID password. AES-256-GCM in transit, HSM-backed escrow keys at rest.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(node.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var nodeTypeLabel: String {
        switch node.nodeType {
        case .thisDevice: return "This Device"
        case .icloud: return "iCloud"
        case .pairedDevice: return "Paired Device"
        case .server: return "MPC Server"
        }
    }

    private func keySyncedToICloud(_ key: ManagedKey) -> Bool {
        KeychainSyncManager.load(keyId: key.id) != nil
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1 { return "\(bytes) B" }
        return String(format: "%.1f KB", kb)
    }
}

// MARK: - Key On Node Row

struct KeyOnNodeRow: View {
    let key: ManagedKey

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: key.keyType == .hdMaster ? "key.radiowaves.forward" : "key.fill")
                .font(.system(size: 12))
                .foregroundColor(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(key.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Text(key.shortAddress)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(key.displayKeyType)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.gray.opacity(0.15))
                .cornerRadius(3)
        }
    }
}

// MARK: - Key Distribution Row

struct KeyDistributionRow: View {
    let key: ManagedKey
    let nodes: [NetworkNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(key.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text(key.shortAddress)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                ForEach(nodes) { node in
                    if nodeHasKey(node, key) {
                        HStack(spacing: 3) {
                            Image(systemName: node.icon)
                                .font(.system(size: 8))
                            Text(shortNodeName(node))
                                .font(.system(size: 8, design: .monospaced))
                        }
                        .foregroundColor(node.status.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(node.status.color.opacity(0.1))
                        .cornerRadius(3)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func nodeHasKey(_ node: NetworkNode, _ key: ManagedKey) -> Bool {
        switch node.nodeType {
        case .thisDevice:
            return true // All keys exist on this device (UserDefaults)
        case .icloud:
            return KeychainSyncManager.load(keyId: key.id) != nil
        default:
            return false
        }
    }

    private func shortNodeName(_ node: NetworkNode) -> String {
        switch node.nodeType {
        case .thisDevice: return "Device"
        case .icloud: return "iCloud"
        case .pairedDevice: return node.name
        case .server: return "Server"
        }
    }
}
