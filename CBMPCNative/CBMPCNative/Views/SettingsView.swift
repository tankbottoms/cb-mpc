import SwiftUI
import CryptoKit
import Security

struct SettingsView: View {
    @EnvironmentObject var keyStore: KeyStore
    @ObservedObject var pairingManager = PairingManager.shared
    @AppStorage("serverUrl") private var serverUrl = "https://api.cbmpc.atsignhandle.xyz"
    @State private var useMockServer = false
    @AppStorage("signingServerURL") private var signingServerURL = "https://signing.cbmpc.atsignhandle.xyz/submit"
    @AppStorage("instructionLevel") private var instructionLevel = "verbose"
    @AppStorage("ethereumRPC") private var ethereumRPC = "mainnet"
    @AppStorage("infuraAPIKey") private var infuraAPIKey = "65980db64d52417abbda13b49e356d97"
    @AppStorage("exportFormat") private var exportFormat = "keystoreJSON"
    @AppStorage("useFaceID") private var useFaceID = false
    @AppStorage("keystorePasswordHash") private var keystorePasswordHash = ""
    @AppStorage("keystorePasswordSetDate") private var keystorePasswordSetDate = ""
    @AppStorage("hdChildNamingUseSelf") private var hdChildNamingUseSelf = false
    @AppStorage("qrTransferSpeed") private var qrTransferSpeed: Double = 1.5
    @AppStorage("etherscanAPIKey") private var etherscanAPIKey = "UWD3H7R1R6SXRUSW9R7SXYX3HUNQYC75W1"
    @AppStorage("rpcProvider") private var rpcProvider = "buidlguidl"

    @State private var showPasswordSheet = false
    @State private var showBackupSheet = false
    @State private var revealInfuraKey = false
    @State private var revealEtherscanKey = false

    // RPC health check state
    @State private var rpcTestResult: String?
    @State private var rpcTestLatency: Int?
    @State private var rpcTestError: String?
    @State private var rpcTesting = false

    // Etherscan chain support test state
    @State private var chainSupportResults: [String: EtherscanService.ChainSupportStatus] = [:]
    @State private var isTestingChains = false
    @AppStorage("etherscanChainSupport") private var cachedChainSupport = ""

    private var currentRPCEndpoint: String {
        RPCService.endpoint(network: ethereumRPC, provider: rpcProvider, infuraKey: infuraAPIKey)
    }

    private var rpcProviderName: String {
        if ethereumRPC == "mainnet" {
            return RPCService.freeMainnetProviders.first(where: { $0.key == rpcProvider })?.name ?? rpcProvider
        }
        return "Infura"
    }

    private var chainId: String {
        EtherscanService.chainId(for: ethereumRPC)
    }

    private var networkDisplayName: String {
        switch ethereumRPC {
        case "mainnet": return "Ethereum Mainnet"
        case "sepolia": return "Sepolia Testnet"
        case "base": return "Base"
        case "arbitrum": return "Arbitrum One"
        case "optimism": return "Optimism"
        case "polygon": return "Polygon"
        case "bsc": return "BNB Smart Chain"
        default: return "Hoodi Testnet"
        }
    }

    private static let allChains = ["mainnet", "sepolia", "base", "arbitrum", "optimism", "polygon", "bsc"]

    // MARK: - Storage Usage

    private var deviceKeychainUsage: String {
        var totalBytes = 0
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "xyz.atsignhandle.cb-mpc.keystore",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let items = result as? [Data] {
            totalBytes = items.reduce(0) { $0 + $1.count }
            let kb = Double(totalBytes) / 1024.0
            return String(format: "%.1f KB (%d items)", kb, items.count)
        }
        return "0 KB (0 items)"
    }

    private var icloudKeychainUsage: String {
        var totalBytes = 0
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "xyz.atsignhandle.cb-mpc.icloud-sync",
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let items = result as? [Data] {
            totalBytes = items.reduce(0) { $0 + $1.count }
            let kb = Double(totalBytes) / 1024.0
            return String(format: "%.1f KB (%d items)", kb, items.count)
        }
        return "0 KB (0 items)"
    }

    private var userDefaultsUsage: String {
        let defaults = UserDefaults.standard
        let keyPrefix = "key_"
        let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(keyPrefix) }
        var totalBytes = 0
        for key in allKeys {
            if let data = defaults.data(forKey: key) {
                totalBytes += data.count
            }
        }
        let kb = Double(totalBytes) / 1024.0
        return String(format: "%.1f KB (%d entries)", kb, allKeys.count)
    }

    private var totalStorageUsage: String {
        // Parse KB values from each tier
        func parseKB(_ s: String) -> Double {
            let parts = s.components(separatedBy: " ")
            return Double(parts.first ?? "0") ?? 0
        }
        let total = parseKB(deviceKeychainUsage) + parseKB(icloudKeychainUsage) + parseKB(userDefaultsUsage)
        return String(format: "%.1f KB", total)
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (build \(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Storage & Security"), footer:
                    Text("Shows where key data is stored and the security properties of each tier. Tap a tier to learn more.")
                        .font(.system(size: 10, design: .monospaced))
                ) {
                    StorageTierRow(
                        icon: "lock.shield",
                        name: "Device Keychain",
                        detail: "AES-256 encrypted at rest by iOS data protection. Tied to device hardware UID. Never leaves this device. Requires unlock (passcode/Face ID).",
                        usage: deviceKeychainUsage
                    )
                    StorageTierRow(
                        icon: "icloud.fill",
                        name: "iCloud Keychain",
                        detail: "Apple end-to-end encrypted. Syncs across devices signed into same Apple ID. Protected by device passcode + Apple ID password. AES-256-GCM in transit, HSM-backed escrow at rest.",
                        usage: icloudKeychainUsage
                    )
                    StorageTierRow(
                        icon: "internaldrive",
                        name: "UserDefaults",
                        detail: "Local app storage for key share data. Protected by iOS app sandbox and device-level encryption (NSFileProtectionComplete).",
                        usage: userDefaultsUsage
                    )

                    HStack {
                        Text("Total")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Spacer()
                        Text(totalStorageUsage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    // Paired devices
                    ForEach(pairingManager.pairedDevices) { device in
                        let connState = pairingManager.connectionState(for: device.id)
                        let isConnected = connState == .connected
                        let deviceColor: Color = isConnected ? .green : (device.isOnline ? .green : .orange)
                        HStack(spacing: 10) {
                            Image(systemName: device.deviceModel.lowercased().contains("ipad") ? "ipad" : "iphone")
                                .font(.system(size: 14))
                                .foregroundColor(deviceColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(device.name)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    Circle()
                                        .fill(deviceColor)
                                        .frame(width: 6, height: 6)
                                }
                                Text("\(device.deviceModel) · \(device.shareCount) key\(device.shareCount == 1 ? "" : "s")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }

                    // Servers
                    ForEach(pairingManager.servers) { server in
                        let serverColor: Color = server.isOnline ? .green : .orange
                        HStack(spacing: 10) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 14))
                                .foregroundColor(server.isRegistered ? serverColor : .gray)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(server.name)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    Circle()
                                        .fill(server.isRegistered ? serverColor : .gray)
                                        .frame(width: 6, height: 6)
                                }
                                Text("\(server.isRegistered ? "Registered" : "Unregistered") · \(server.shareCount) key\(server.shareCount == 1 ? "" : "s")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                Section(header: Text("RPC Provider"), footer:
                    Text("Connects to the Ethereum network for broadcasting transactions and querying on-chain state. Mainnet uses free public RPC endpoints. Other networks require an Infura API key.")
                        .font(.system(size: 10, design: .monospaced))
                ) {
                    Picker("Network", selection: $ethereumRPC) {
                        Text("Ethereum Mainnet").tag("mainnet")
                        Text("Base").tag("base")
                        Text("Arbitrum One").tag("arbitrum")
                        Text("Optimism").tag("optimism")
                        Text("Polygon").tag("polygon")
                        Text("BNB Smart Chain").tag("bsc")
                        Text("Sepolia (Testnet)").tag("sepolia")
                        Text("Hoodi (Testnet)").tag("hoodi")
                    }
                    .pickerStyle(.menu)

                    if ethereumRPC == "mainnet" {
                        Picker("RPC Provider", selection: $rpcProvider) {
                            ForEach(RPCService.freeMainnetProviders, id: \.key) { provider in
                                Text(provider.name).tag(provider.key)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Text("RPC URL")
                        Spacer()
                        Text(currentRPCEndpoint)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }

                    if ethereumRPC != "mainnet" {
                        apiKeyRow(label: "Infura API Key", key: $infuraAPIKey, revealed: $revealInfuraKey)
                    }

                    HStack {
                        Text("Chain ID")
                        Spacer()
                        Text(chainId)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    // RPC Health Check
                    Button(action: testRPCConnection) {
                        HStack(spacing: 8) {
                            if rpcTesting {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Testing...")
                                    .font(.system(size: 12, design: .monospaced))
                            } else {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 12))
                                Text("Test Connection")
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                    }
                    .disabled(rpcTesting)

                    if let block = rpcTestResult, let ms = rpcTestLatency {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            Text("Block \(block)")
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text("\(ms)ms")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let err = rpcTestError {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 12))
                            Text(err)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    }
                }

                Section(header: Text("Etherscan API"), footer:
                    Text("Gas oracle, ETH/USD pricing, and contract lookups are provided by the Etherscan v2 API. Free tier works on mainnet and polygon. Other chains may require a paid API key.")
                        .font(.system(size: 10, design: .monospaced))
                ) {
                    apiKeyRow(label: "API Key", key: $etherscanAPIKey, revealed: $revealEtherscanKey)

                    // Chain support badges
                    Button(action: testEtherscanChains) {
                        HStack(spacing: 8) {
                            if isTestingChains {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Testing chains...")
                                    .font(.system(size: 12, design: .monospaced))
                            } else {
                                Image(systemName: "network")
                                    .font(.system(size: 12))
                                Text("Test Chain Support")
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                    }
                    .disabled(isTestingChains)

                    if !chainSupportResults.isEmpty {
                        ForEach(Self.allChains, id: \.self) { chain in
                            if let status = chainSupportResults[chain] {
                                chainSupportRow(chain: chain, status: status)
                            }
                        }
                    }
                }

                Section(header: Text("Server Configuration"), footer:
                    Text("Server URL is used for distributed key generation (DKG) and multi-party computation coordination between parties. Signing Server handles commitment exchanges and threshold signature assembly for transaction signing.")
                        .font(.system(size: 10, design: .monospaced))
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server URL")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        TextField("https://api.cbmpc.atsignhandle.xyz", text: $serverUrl)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Signing Server")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        TextField("https://signing.cbmpc.atsignhandle.xyz/submit", text: $signingServerURL)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    }

                    Toggle("Use Mock Server", isOn: $useMockServer)
                }

                Section(header: Text("Export Format"), footer:
                    Text("KeyStore V3 JSON includes MPC key shares for full backup and restore capability. This is the only supported export format.")
                        .font(.system(size: 10, design: .monospaced))
                ) {
                    HStack {
                        Text("Format")
                        Spacer()
                        Text("KeyStore V3 JSON")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Security"), footer:
                    Text("Protects access to keys and signing operations. Face ID provides biometric authentication on app launch. Password is required as fallback when Face ID is unavailable.")
                        .font(.system(size: 10, design: .monospaced))
                ) {
                    Toggle("Face ID", isOn: $useFaceID)

                    HStack {
                        Text("Password")
                        Spacer()
                        if !keystorePasswordHash.isEmpty {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Enabled")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                                if !keystorePasswordSetDate.isEmpty {
                                    Text("Set \(keystorePasswordSetDate)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Text("Disabled")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showPasswordSheet = true
                    }
                }

                Section(header: Text("Key Naming"), footer:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hdChildNamingUseSelf
                            ? "HD-CHILD keys are named using their own 0x address."
                            : "HD-CHILD keys are named as {HD-MASTER 0x address}/{account number} {timestamp}.")
                        Text("Toggle on to use the child's own 0x address instead. The HD-MASTER address is always visible in Key Details under the derivation path.")
                    }
                    .font(.system(size: 10, design: .monospaced))
                ) {
                    Toggle("HD-CHILD uses own address", isOn: $hdChildNamingUseSelf)
                }

                Section(header: Text("QR Transfer"), footer:
                    Text("Controls the cycling speed of animated QR codes when exporting keys for transfer to another device.")
                        .font(.system(size: 10, design: .monospaced))
                ) {
                    HStack {
                        Text("Cycle Speed")
                        Spacer()
                        Text("\(String(format: "%.1f", qrTransferSpeed))s")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $qrTransferSpeed, in: 0.5...3.0, step: 0.25)
                }

                Section(header: Text("Display")) {
                    Picker("Instruction Level", selection: $instructionLevel) {
                        Text("Off").tag("off")
                        Text("Minimal").tag("minimal")
                        Text("Verbose").tag("verbose")
                    }
                }

                Section(header: Text("Sync & Backup"), footer:
                    Text("Exports all keys as KeyStore V3 JSON files to iCloud Documents/Key-MGMT-CB-MPC with UTC timestamp filenames for recovery across devices.")
                        .font(.system(size: 10, design: .monospaced))
                ) {
                    Button(action: { showBackupSheet = true }) {
                        Label("Backup to iCloud Now", systemImage: "icloud.and.arrow.up")
                            .font(.system(size: 13))
                    }
                    .disabled(keyStore.keys.isEmpty)

                    Button(action: {
                        keyStore.seedDemoData()
                    }) {
                        if keyStore.isSeedingDemoData {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Generating keys...")
                                    .font(.system(size: 13))
                            }
                        } else {
                            Label("Reset Demo Data", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 13))
                        }
                    }
                    .disabled(keyStore.isSeedingDemoData)
                }

                Section(header: Text("App Info"), footer:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TESTFLIGHT BETA")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                        Text("While in beta TestFlight, app icons feature party-themed MeowsDAO cats. These will be replaced with a proper MPC-themed icon once the design is finalized.")
                            .font(.system(size: 10, design: .monospaced))

                        Text("DISCLAIMER")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.top, 4)
                        Text("This application is in active development and is provided as-is for testing and evaluation purposes only. It is not intended for production use or for managing real cryptocurrency assets. Use at your own risk.")
                            .font(.system(size: 10, design: .monospaced))

                        Text("ACKNOWLEDGEMENTS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.top, 4)
                        Text("Built on Coinbase CB-MPC, an open-source threshold cryptography library implementing multi-party ECDSA and EdDSA signature protocols. This application is an independent fork created for research and educational purposes. Thanks to the broader cryptocurrency research community for their contributions to threshold signature schemes, hierarchical deterministic key derivation standards (BIP-32/44), and advances in secure multi-party computation.")
                            .font(.system(size: 10, design: .monospaced))
                    }
                ) {
                    HStack {
                        Text("Version")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(versionString)
                            .font(.system(.caption, design: .monospaced))
                    }

                    Link(destination: URL(string: "https://github.com/coinbase/cb-mpc")!) {
                        HStack {
                            Text("Coinbase CB-MPC")
                                .font(.system(size: 13))
                            Spacer()
                            Text("github.com/coinbase/cb-mpc")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://github.com/tankbottoms/cb-mpc")!) {
                        HStack {
                            Text("iOS Application")
                                .font(.system(size: 13))
                            Spacer()
                            Text("github.com/tankbottoms/cb-mpc")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Extra bottom space so App Info clears the floating tab bar
                Section {
                    EmptyView()
                }
                .listRowBackground(Color.clear)
                .frame(height: 140)
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            #endif
            .sheet(isPresented: $showPasswordSheet) {
                PasswordSetupSheetView(
                    keystorePasswordHash: $keystorePasswordHash,
                    keystorePasswordSetDate: $keystorePasswordSetDate
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showBackupSheet) {
                BackupSheetView()
                    .environmentObject(keyStore)
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                loadCachedChainSupport()
            }
        }
    }

    private func testRPCConnection() {
        rpcTesting = true
        rpcTestResult = nil
        rpcTestLatency = nil
        rpcTestError = nil
        Task {
            do {
                let result = try await RPCService.testConnection(url: currentRPCEndpoint)
                await MainActor.run {
                    rpcTestResult = result.blockNumber
                    rpcTestLatency = result.latencyMs
                    rpcTesting = false
                }
            } catch {
                await MainActor.run {
                    rpcTestError = error.localizedDescription
                    rpcTesting = false
                }
            }
        }
    }

    private func testEtherscanChains() {
        isTestingChains = true
        chainSupportResults = [:]
        Task {
            var results: [String: EtherscanService.ChainSupportStatus] = [:]
            for chain in Self.allChains {
                let status = await EtherscanService.testChainSupport(apiKey: etherscanAPIKey, chain: chain)
                results[chain] = status
                await MainActor.run {
                    chainSupportResults = results
                }
            }
            // Cache results
            if let data = try? JSONEncoder().encode(results),
               let json = String(data: data, encoding: .utf8) {
                await MainActor.run {
                    cachedChainSupport = json
                    isTestingChains = false
                }
            } else {
                await MainActor.run {
                    isTestingChains = false
                }
            }
        }
    }

    private func loadCachedChainSupport() {
        guard !cachedChainSupport.isEmpty,
              let data = cachedChainSupport.data(using: .utf8),
              let results = try? JSONDecoder().decode([String: EtherscanService.ChainSupportStatus].self, from: data) else {
            return
        }
        chainSupportResults = results
    }

    @ViewBuilder
    private func chainSupportRow(chain: String, status: EtherscanService.ChainSupportStatus) -> some View {
        let name: String = {
            switch chain {
            case "mainnet": return "Ethereum Mainnet"
            case "sepolia": return "Sepolia"
            case "base": return "Base"
            case "arbitrum": return "Arbitrum"
            case "optimism": return "Optimism"
            case "polygon": return "Polygon"
            case "bsc": return "BNB Chain"
            default: return chain
            }
        }()

        HStack(spacing: 8) {
            switch status {
            case .free:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            case .paid:
                Image(systemName: "lock.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 12))
            case .unsupported:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            }
            Text(name)
                .font(.system(size: 11, design: .monospaced))
            Spacer()
            Text(status == .free ? "Free" : status == .paid ? "Paid Key Required" : "Not Supported")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func apiKeyRow(label: String, key: Binding<String>, revealed: Binding<Bool>) -> some View {
        HStack {
            Text(label)
            Spacer()
            if revealed.wrappedValue {
                TextField("API Key", text: key)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                Text(String(repeating: "*", count: min(key.wrappedValue.count, 20)))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Button(action: { revealed.wrappedValue.toggle() }) {
                Image(systemName: revealed.wrappedValue ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Storage Tier Row

struct StorageTierRow: View {
    let icon: String
    let name: String
    let detail: String
    let usage: String

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation { expanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                        Text(usage)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(.blue.opacity(0.05))
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - Backup Sheet

struct BackupSheetView: View {
    @EnvironmentObject var keyStore: KeyStore
    @Environment(\.dismiss) var dismiss

    @State private var backupLog: [String] = []
    @State private var isBackingUp = false
    @State private var backupComplete = false
    @State private var backupProgress: Int = 0
    @State private var backupTotal: Int = 0
    @State private var backupError: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ICLOUD BACKUP")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))

                    Text("Export all keys as KeyStore V3 JSON to iCloud Documents/Key-MGMT-CB-MPC. Each key is saved with UTC timestamp filename.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(.blue.opacity(0.05))
                .cornerRadius(6)

                // Terminal-style log output
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(backupLog.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .id(idx)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: backupLog.count) { _ in
                        if let last = backupLog.indices.last {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
                .padding(10)
                .background(.blue.opacity(0.05))
                .cornerRadius(6)
                .frame(maxHeight: .infinity)

                if isBackingUp {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Backing up \(backupProgress)/\(backupTotal)...")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }

                if let err = backupError {
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red)
                }

                HStack(spacing: 8) {
                    if backupComplete {
                        Button("OK") { dismiss() }
                            .font(.system(size: 14, design: .monospaced))
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    } else if isBackingUp {
                        Button("Cancel") { dismiss() }
                            .font(.system(size: 14, design: .monospaced))
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    } else {
                        Button("Cancel") { dismiss() }
                            .font(.system(size: 14, design: .monospaced))
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)

                        Button("Start Backup") { startBackup() }
                            .font(.system(size: 14, design: .monospaced))
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(keyStore.keys.isEmpty)
                    }
                }
            }
            .padding(16)
            .navigationTitle("Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func startBackup() {
        guard !isBackingUp else { return }
        isBackingUp = true
        backupError = nil
        backupProgress = 0
        backupTotal = keyStore.keys.count
        backupLog = []

        let timeStr = AppDateFormat.string(from: Date())
        withAnimation { backupLog.append("[\(timeStr)] Starting backup of \(keyStore.keys.count) key(s)...") }

        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.xyz.atsignhandle.cb-mpc") else {
            backupError = "iCloud not available"
            isBackingUp = false
            withAnimation { backupLog.append("[ERROR] iCloud container not accessible") }
            return
        }

        let backupDir = containerURL.appendingPathComponent("Documents/Key-MGMT-CB-MPC", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            withAnimation { backupLog.append("[OK] iCloud/Key-MGMT-CB-MPC/") }
        } catch {
            backupError = "Failed to create backup folder"
            isBackingUp = false
            withAnimation { backupLog.append("[ERROR] \(error.localizedDescription)") }
            return
        }

        let keys = keyStore.keys
        func backupNext(_ index: Int) {
            guard index < keys.count else {
                let impact = UINotificationFeedbackGenerator()
                impact.notificationOccurred(.success)
                let doneTime = AppDateFormat.string(from: Date())
                withAnimation { backupLog.append("[\(doneTime)] Backup complete -- \(keys.count) keystore(s)") }
                isBackingUp = false
                backupComplete = true
                return
            }

            let key = keys[index]
            withAnimation(.easeInOut(duration: 0.2)) {
                backupProgress = index + 1
            }

            var dict: [String: Any] = [
                "version": 3,
                "id": key.id.uuidString.lowercased(),
                "address": String(key.publicKey.suffix(40)),
                "crypto": [
                    "cipher": "aes-128-ctr",
                    "cipherparams": ["iv": ""],
                    "ciphertext": "",
                    "kdf": "scrypt",
                    "kdfparams": [
                        "dklen": 32,
                        "n": 262144,
                        "p": 1,
                        "r": 8,
                        "salt": ""
                    ],
                    "mac": ""
                ],
                "cb-mpc": [
                    "name": key.name,
                    "publicKey": key.publicKey,
                    "keyType": key.keyType.rawValue,
                    "curveCode": Int(key.curveCode),
                    "createdAt": ISO8601DateFormatter().string(from: key.createdAt),
                    "storageLocation": key.storageLocation.rawValue
                ]
            ]
            if let path = key.derivationPath {
                var cbmpc = dict["cb-mpc"] as? [String: Any] ?? [:]
                cbmpc["derivationPath"] = path
                dict["cb-mpc"] = cbmpc
            }
            if let parentId = key.parentKeyId {
                var cbmpc = dict["cb-mpc"] as? [String: Any] ?? [:]
                cbmpc["parentKeyId"] = parentId.uuidString
                dict["cb-mpc"] = cbmpc
            }
            if let keyData = UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") {
                var cbmpc = dict["cb-mpc"] as? [String: Any] ?? [:]
                cbmpc["keyData"] = keyData.base64EncodedString()
                dict["cb-mpc"] = cbmpc
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            let timestamp = formatter.string(from: key.createdAt)
            let addr = String(key.publicKey.suffix(40))
            let fileName = "UTC--\(timestamp)--\(addr).json"
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                let fileURL = backupDir.appendingPathComponent(fileName)
                try? jsonData.write(to: fileURL, options: .atomic)
                let sizeKB = Double(jsonData.count) / 1024.0
                withAnimation {
                    backupLog.append("  \(key.displayKeyType) 0x\(key.shortAddress) \(String(format: "%.1f", sizeKB))KB")
                    backupLog.append("  -> \(fileName)")
                }
            }

            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                backupNext(index + 1)
            }
        }

        backupNext(0)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("APP LOCK PASSWORD")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))

                    Text("Set a password to lock the app on launch. This password is required when Face ID is unavailable or disabled. The password hash is stored locally using SHA-256.")
                        .font(.system(size: 11, design: .monospaced))
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
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red)
                    } else if passwordsMatch {
                        Text("Passwords match")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    if let err = passwordError {
                        Text(err)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red)
                    }

                    if passwordSaved {
                        Text("Password saved successfully")
                            .font(.system(size: 11, design: .monospaced))
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
