import SwiftUI
import Security
import CryptoKit
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
    @State private var deviceToDelete: PairedDevice?
    @State private var serverToDelete: MPCServer?

    var body: some View {
        NavigationStack {
            List {
                // Fixed nodes (this device + iCloud) — no swipe
                Section(header: Text("THIS DEVICE"), footer:
                    SectionFooterText(text: "Local storage locations for key shares.")
                ) {
                    ForEach(fixedNodes) { node in
                        NavigationLink(destination: NodeDetailView(node: node, keyStore: keyStore)) {
                            NodeRow(node: node)
                        }
                    }
                }

                // Paired devices — swipe-to-delete
                if !pairedDeviceNodes.isEmpty {
                    Section(header: Text("PAIRED DEVICES")) {
                        ForEach(pairedDeviceNodes) { node in
                            NavigationLink(destination: NodeDetailView(node: node, keyStore: keyStore)) {
                                NodeRow(node: node)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let device = pairingManager.pairedDevices.first(where: { $0.id.uuidString == node.id }) {
                                        deviceToDelete = device
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                // Servers — swipe-to-delete
                if !serverNodes.isEmpty {
                    Section(header: Text("SERVERS")) {
                        ForEach(serverNodes) { node in
                            NavigationLink(destination: NodeDetailView(node: node, keyStore: keyStore)) {
                                NodeRow(node: node)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let server = pairingManager.servers.first(where: { $0.id.uuidString == node.id }) {
                                        serverToDelete = server
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
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
            .alert("Delete Device", isPresented: Binding(
                get: { deviceToDelete != nil },
                set: { if !$0 { deviceToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { deviceToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let device = deviceToDelete {
                        pairingManager.removePairedDevice(device)
                        refreshNodes()
                    }
                    deviceToDelete = nil
                }
            } message: {
                Text("Remove \"\(deviceToDelete?.name ?? "this device")\" from paired devices? This cannot be undone.")
            }
            .alert("Delete Server", isPresented: Binding(
                get: { serverToDelete != nil },
                set: { if !$0 { serverToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { serverToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let server = serverToDelete {
                        pairingManager.removeServer(server)
                        refreshNodes()
                    }
                    serverToDelete = nil
                }
            } message: {
                Text("Remove \"\(serverToDelete?.name ?? "this server")\"? Auth tokens will be deleted from Keychain.")
            }
        }
    }

    // MARK: - Node Filters

    private var fixedNodes: [NetworkNode] {
        nodes.filter { $0.nodeType == .thisDevice || $0.nodeType == .icloud }
    }

    private var pairedDeviceNodes: [NetworkNode] {
        nodes.filter { $0.nodeType == .pairedDevice }
    }

    private var serverNodes: [NetworkNode] {
        nodes.filter { $0.nodeType == .server }
    }

    // MARK: - Refresh

    private func refreshNodes() {
        isRefreshing = true
        var allNodes: [NetworkNode] = []

        allNodes.append(buildThisDeviceNode())
        allNodes.append(buildICloudNode())

        // Add paired devices with live connection status
        for device in pairingManager.pairedDevices {
            let connState = pairingManager.connectionState(for: device.id)
            let isConnected = connState == .connected
            // Derive short fingerprint from public key
            let fingerprint = SHA256.hash(data: device.publicKey)
                .prefix(8)
                .map { String(format: "%02X", $0) }
                .joined(separator: ":")
            let isIPad = device.deviceModel.lowercased().contains("ipad")
            var pairedNode = NetworkNode(
                id: device.id.uuidString,
                name: device.name,
                icon: isIPad ? "ipad" : "iphone",
                nodeType: .pairedDevice,
                status: isConnected ? .active : (device.isOnline ? .active : .offline),
                shareCount: device.shareCount,
                keychainItems: 0,
                keychainBytes: 0,
                userDefaultsEntries: 0,
                userDefaultsBytes: 0,
                deviceModel: device.deviceModel,
                lastSeen: device.lastSeenAt,
                vendorId: fingerprint
            )
            pairedNode.pairedAt = device.pairedAt
            allNodes.append(pairedNode)
        }

        // Add servers with async health check
        for (index, server) in pairingManager.servers.enumerated() {
            let serverStatus: NetworkNode.NodeStatus
            if server.isRegistered {
                serverStatus = server.isOnline ? .active : .offline
            } else {
                serverStatus = .empty // unregistered
            }

            allNodes.append(NetworkNode(
                id: server.id.uuidString,
                name: server.name,
                icon: "server.rack",
                nodeType: .server,
                status: serverStatus,
                shareCount: server.shareCount,
                keychainItems: 0,
                keychainBytes: 0,
                userDefaultsEntries: 0,
                userDefaultsBytes: 0,
                deviceModel: server.url,
                lastSeen: server.lastSeenAt,
                isRegistered: server.isRegistered
            ))

            // Async health check for each server
            if let baseURL = URL(string: server.url) {
                let serverIndex = index
                Task {
                    let client = ServerAPIClient(baseURL: baseURL)
                    do {
                        _ = try await client.health()
                        await MainActor.run {
                            pairingManager.servers[serverIndex].isOnline = true
                            pairingManager.servers[serverIndex].lastSeenAt = Date()
                            pairingManager.saveServers()
                        }
                    } catch {
                        await MainActor.run {
                            pairingManager.servers[serverIndex].isOnline = false
                            pairingManager.saveServers()
                        }
                    }
                }
            }
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

        var thisNode = NetworkNode(
            id: "this-device",
            name: DeviceInfo.deviceName,
            icon: "iphone",
            nodeType: .thisDevice,
            status: .active,
            shareCount: keyStore.keys.count,
            keychainItems: kcCount,
            keychainBytes: kcBytes,
            userDefaultsEntries: udKeys.count,
            userDefaultsBytes: udBytes,
            deviceModel: DeviceInfo.modelName,
            lastSeen: Date(),
            vendorId: DeviceInfo.vendorIdentifier,
            hardwareId: DeviceInfo.hardwareIdentifier,
            iCloudAvailable: DeviceInfo.isICloudAvailable
        )
        thisNode.ipAddress = DeviceInfo.wifiIPAddress
        return thisNode
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
    var isRegistered: Bool = false
    var vendorId: String?
    var hardwareId: String?
    var iCloudAvailable: Bool = false
    var pairedAt: Date?
    var ipAddress: String?

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
                        .font(CBStyle.Fonts.bodyMedium)
                        .lineLimit(1)
                    NodeStatusDot(color: node.status.color)
                }

                if let model = node.deviceModel, node.nodeType == .thisDevice || node.nodeType == .pairedDevice {
                    Text(model)
                        .font(CBStyle.Fonts.crypto)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    TagBadge(text: node.status.rawValue, color: node.status.color)

                    if node.nodeType == .server && node.isRegistered {
                        TagBadge(text: "Registered", color: .blue)
                    }

                    if node.iCloudAvailable && node.nodeType == .thisDevice {
                        HStack(spacing: 2) {
                            Image(systemName: "icloud.fill")
                                .font(.system(size: 8))
                            Text("iCloud")
                                .font(CBStyle.Fonts.badge)
                        }
                        .foregroundColor(.blue)
                    }

                    if node.shareCount > 0 {
                        Text("\(node.shareCount) key\(node.shareCount == 1 ? "" : "s")")
                            .font(CBStyle.Fonts.caption)
                            .foregroundColor(.secondary)
                    }

                    if node.totalBytes > 0 {
                        Text(node.totalBytesDisplay)
                            .font(CBStyle.Fonts.caption)
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

    private var pairedDevice: PairedDevice? {
        PairingManager.shared.pairedDevices.first(where: { $0.id.uuidString == node.id })
    }

    private var mpcServer: MPCServer? {
        PairingManager.shared.servers.first(where: { $0.id.uuidString == node.id })
    }

    /// Keys co-signed with this node
    private var coSignedKeys: [ManagedKey] {
        if node.nodeType == .pairedDevice {
            return TransportOrigin.keysWithCoSigner(node.id, in: keyStore.keys)
        } else if node.nodeType == .server, let server = mpcServer {
            return TransportOrigin.keysWithCoSigner(server.url, in: keyStore.keys)
        }
        return []
    }

    /// Signing records for keys co-signed with this node
    private var signingHistory: [(key: ManagedKey, record: SigningRecord)] {
        coSignedKeys.flatMap { key in
            key.signingRecords.map { (key: key, record: $0) }
        }
        .sorted { $0.record.timestamp > $1.record.timestamp }
    }

    var body: some View {
        List {
            // Reconnect button for paired devices
            if node.nodeType == .pairedDevice, let device = pairedDevice {
                Section {
                    let connState = PairingManager.shared.connectionState(for: device.id)
                    Button(action: { PairingManager.shared.reconnect(to: device) }) {
                        Label(connState == .connected ? "Connected" : "Reconnect",
                              systemImage: connState == .connected ? "link" : "arrow.triangle.2.circlepath")
                    }
                    .disabled(connState == .connected || connState == .connecting)
                }
            }

            // Server connection badge
            if node.nodeType == .server, let server = mpcServer {
                Section {
                    HStack {
                        Image(systemName: server.isOnline ? "bolt.fill" : "bolt.slash")
                            .foregroundColor(server.isOnline ? .green : .orange)
                        Text(server.isOnline ? "Connected" : "Disconnected")
                            .font(CBStyle.Fonts.cryptoMedium)
                        Spacer()
                        if !server.isOnline {
                            Button("Ping") {
                                PairingManager.shared.pingServer(server) { online, _ in
                                    if let idx = PairingManager.shared.servers.firstIndex(where: { $0.id == server.id }) {
                                        PairingManager.shared.servers[idx].isOnline = online
                                        PairingManager.shared.saveServers()
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section(header: Text("NODE INFO")) {
                InfoRow(label: "Name", value: node.name)
                // Type row: show IP for this device, keep labels for others
                if node.nodeType == .thisDevice {
                    InfoRow(label: "IP Address", value: node.ipAddress ?? "WiFi")
                } else {
                    InfoRow(label: "Type", value: nodeTypeLabel)
                }
                InfoRow(label: "Status", value: node.status.rawValue)
                if let model = node.deviceModel, node.nodeType != .server {
                    InfoRow(label: "Model", value: model)
                }
                if let vendorId = node.vendorId, node.nodeType == .thisDevice {
                    InfoRow(label: "Vendor ID", value: vendorId)
                }
                if node.iCloudAvailable {
                    HStack {
                        Text("iCloud")
                            .font(CBStyle.Fonts.crypto)
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.icloud.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text("Signed In")
                                .font(CBStyle.Fonts.crypto)
                                .foregroundColor(.blue)
                        }
                    }
                }
                if let seen = node.lastSeen {
                    InfoRow(label: "Last Seen", value: formatDate(seen))
                }
            }

            // iCloud identity section
            if node.nodeType == .icloud {
                Section(header: Text("ICLOUD IDENTITY")) {
                    if let token = FileManager.default.ubiquityIdentityToken {
                        if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false) {
                            let hash = SHA256.hash(data: tokenData).prefix(8).map { String(format: "%02x", $0) }.joined()
                            InfoRow(label: "iCloud ID", value: hash)
                        }
                    } else {
                        InfoRow(label: "iCloud", value: "Not signed in")
                    }
                }
            }

            // Paired device details
            if node.nodeType == .pairedDevice, let device = pairedDevice {
                Section(header: Text("PAIRING INFO")) {
                    InfoRow(label: "Paired", value: formatAbsoluteDate(device.pairedAt))
                    InfoRow(label: "Device Model", value: device.deviceModel)
                    if let vendorId = node.vendorId {
                        InfoRow(label: "Fingerprint", value: vendorId)
                    }
                    if let token = device.discoveryToken {
                        InfoRow(label: "Discovery Token", value: String(token.prefix(16)) + "...")
                    }
                    let connState = PairingManager.shared.connectionState(for: device.id)
                    InfoRow(label: "Connection", value: connectionLabel(connState))
                    if let lastSeen = device.lastSeenAt {
                        InfoRow(label: "Last Active", value: formatDate(lastSeen))
                    }
                }
            }

            // Server details
            if node.nodeType == .server, let server = mpcServer {
                Section(header: Text("SERVER INFO")) {
                    InfoRow(label: "URL", value: server.url)
                    InfoRow(label: "Registered", value: formatAbsoluteDate(server.registeredAt))
                    if let devId = server.serverDeviceId {
                        InfoRow(label: "Device ID", value: devId)
                    }
                    if let version = server.apiVersion {
                        InfoRow(label: "API Version", value: version)
                    }
                    InfoRow(label: "Auth", value: server.isRegistered ? "Authenticated" : "Not registered")
                }
            }

            // Device identity (this device only) — Hardware ID only here, not in NODE INFO
            if node.nodeType == .thisDevice {
                Section(header: Text("DEVICE IDENTITY")) {
                    if let vendorId = node.vendorId {
                        InfoRow(label: "Vendor ID", value: vendorId)
                    }
                    if let hwId = node.hardwareId {
                        InfoRow(label: "Hardware ID", value: hwId)
                    }
                }
            }

            Section(header: Text("STORAGE")) {
                if node.nodeType == .thisDevice {
                    InfoRow(label: "Device Keychain", value: "\(node.keychainItems) item\(node.keychainItems == 1 ? "" : "s") (\(formatBytes(node.keychainBytes)))")
                    InfoRow(label: "UserDefaults", value: "\(node.userDefaultsEntries) entr\(node.userDefaultsEntries == 1 ? "y" : "ies") (\(formatBytes(node.userDefaultsBytes)))")
                    InfoRow(label: "Total", value: node.totalBytesDisplay)
                } else if node.nodeType == .icloud {
                    InfoRow(label: "Synced Items", value: "\(node.keychainItems) item\(node.keychainItems == 1 ? "" : "s")")
                    InfoRow(label: "Size", value: formatBytes(node.keychainBytes))
                } else if node.nodeType == .server || node.nodeType == .pairedDevice {
                    InfoRow(label: "Co-signed Keys", value: "\(coSignedKeys.count) key\(coSignedKeys.count == 1 ? "" : "s")")
                }
            }

            // Co-signed keys section (for paired devices and servers)
            if !coSignedKeys.isEmpty {
                Section(header: Text("CO-SIGNED KEYS")) {
                    ForEach(coSignedKeys) { key in
                        HStack(spacing: 8) {
                            Image(systemName: key.keyType == .hdMaster ? "key.radiowaves.forward" : "key.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key.name)
                                    .font(CBStyle.Fonts.cryptoMedium)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(key.shortAddress)
                                        .font(CBStyle.Fonts.badge)
                                        .foregroundColor(.secondary)
                                    Text(formatAbsoluteDate(key.createdAt))
                                        .font(CBStyle.Fonts.badge)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            TagBadge(text: key.displayKeyType)
                        }
                    }
                }
            }

            // Keys on this node (for this device and iCloud)
            if node.nodeType == .thisDevice && node.shareCount > 0 {
                Section(header: Text("ALL KEYS")) {
                    ForEach(keyStore.keys) { key in
                        KeyOnNodeRow(key: key)
                    }
                }
            } else if node.nodeType == .icloud && node.shareCount > 0 {
                Section(header: Text("SYNCED KEYS")) {
                    ForEach(keyStore.keys.filter { keySyncedToICloud($0) }) { key in
                        KeyOnNodeRow(key: key)
                    }
                    if keyStore.keys.filter({ keySyncedToICloud($0) }).isEmpty {
                        Text("No keys synced to iCloud Keychain")
                            .font(CBStyle.Fonts.crypto)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Signing history (for paired devices and servers)
            if !signingHistory.isEmpty {
                Section(header: Text("SIGNING HISTORY")) {
                    ForEach(signingHistory.prefix(10), id: \.record.id) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.key.name)
                                    .font(CBStyle.Fonts.cryptoMedium)
                                    .lineLimit(1)
                                Spacer()
                                Text(formatDate(entry.record.timestamp))
                                    .font(CBStyle.Fonts.badge)
                                    .foregroundColor(.secondary)
                            }
                            Text(entry.record.messageHash.prefix(32) + "...")
                                .font(CBStyle.Fonts.badge)
                                .foregroundColor(.secondary)
                        }
                    }
                    if signingHistory.count > 10 {
                        Text("\(signingHistory.count - 10) more record\(signingHistory.count - 10 == 1 ? "" : "s")")
                            .font(CBStyle.Fonts.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("SECURITY")) {
                securityDescription
            }
        }
        .navigationTitle(node.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var securityDescription: some View {
        switch node.nodeType {
        case .thisDevice:
            SecurityRow(title: "Device Keychain",
                        description: "AES-256 encrypted at rest by iOS data protection. Tied to device hardware UID. Never leaves this device. Requires unlock (passcode/Face ID).")
            SecurityRow(title: "UserDefaults",
                        description: "Local app storage for key share data. Protected by iOS app sandbox and device-level encryption (NSFileProtectionComplete).")
        case .icloud:
            SecurityRow(title: "iCloud Keychain",
                        description: "Apple end-to-end encrypted. Syncs across devices signed into same Apple ID. Protected by device passcode + Apple ID password. AES-256-GCM in transit, HSM-backed escrow keys at rest.")
        case .pairedDevice:
            SecurityRow(title: "Paired Device",
                        description: "Share transmitted via AES-256 encrypted channel after QR + 6-digit PIN pairing ceremony. Share stored in the paired device's Device Keychain.")
        case .server:
            SecurityRow(title: "MPC Server",
                        description: "Server holds one key share. Authenticated via HMAC token exchanged during device registration. Server cannot sign alone (requires quorum).")
        }
    }

    private var nodeTypeLabel: String {
        switch node.nodeType {
        case .thisDevice: return "This Device"
        case .icloud: return "iCloud"
        case .pairedDevice: return "Paired Device"
        case .server: return "MPC Server"
        }
    }

    private func connectionLabel(_ state: PeerConnectionManager.ConnectionState) -> String {
        switch state {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .searching: return "Searching..."
        case .disconnected: return "Disconnected"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }

    private func keySyncedToICloud(_ key: ManagedKey) -> Bool {
        KeychainSyncManager.load(keyId: key.id) != nil
    }

    private func formatDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func formatAbsoluteDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1 { return "\(bytes) B" }
        return String(format: "%.1f KB", kb)
    }
}

struct SecurityRow: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CBStyle.Fonts.cryptoMedium)
            Text(description)
                .font(CBStyle.Fonts.caption)
                .foregroundColor(.secondary)
        }
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
                    .font(CBStyle.Fonts.cryptoMedium)
                    .lineLimit(1)
                Text(key.shortAddress)
                    .font(CBStyle.Fonts.badge)
                    .foregroundColor(.secondary)
            }
            Spacer()
            TagBadge(text: key.displayKeyType)
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
                    .font(CBStyle.Fonts.cryptoMedium)
                    .lineLimit(1)
                Spacer()
                Text(key.shortAddress)
                    .font(CBStyle.Fonts.badge)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                ForEach(nodes) { node in
                    if nodeHasKey(node, key) {
                        HStack(spacing: 3) {
                            Image(systemName: node.icon)
                                .font(CBStyle.Fonts.tiny)
                            Text(shortNodeName(node))
                                .font(CBStyle.Fonts.tinyMedium)
                        }
                        .foregroundColor(node.status.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(node.status.color.opacity(0.1))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func nodeHasKey(_ node: NetworkNode, _ key: ManagedKey) -> Bool {
        switch node.nodeType {
        case .thisDevice:
            return true
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
