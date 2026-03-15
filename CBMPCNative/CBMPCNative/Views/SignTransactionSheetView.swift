import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SignTransactionSheetView: View {
    let key: ManagedKey
    @Environment(\.dismiss) var dismiss
    @AppStorage("ethereumRPC") private var ethereumRPC = "hoodi"
    @AppStorage("infuraAPIKey") private var infuraAPIKey = "65980db64d52417abbda13b49e356d97"
    @AppStorage("etherscanAPIKey") private var etherscanAPIKey = "UWD3H7R1R6SXRUSW9R7SXYX3HUNQYC75W1"

    @State private var nonce = "0"
    @State private var toAddress = ""
    @State private var value = "0.01"
    @State private var gasLimit = "21000"
    @State private var gasPrice = "20"
    @State private var maxPriorityFee = "1.5"
    @State private var data = ""
    @State private var showShareSheet = false
    @State private var showGasSheet = false
    @State private var showNetworkSelector = false

    // Etherscan live data
    @State private var ethUsdPrice: String?
    @State private var ethBalance: String?
    @State private var gasOracle: EtherscanService.GasOracle?
    @State private var lastBlock: String?
    @State private var isLoadingGas = false
    @State private var apiErrorMessage: String?

    private var chainId: String {
        switch ethereumRPC {
        case "mainnet": return "1"
        case "sepolia": return "11155111"
        case "base": return "8453"
        case "arbitrum": return "42161"
        case "optimism": return "10"
        case "polygon": return "137"
        case "bsc": return "56"
        default: return "560048"
        }
    }

    private var networkName: String {
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

    private var txCostUsd: String? {
        guard let gwei = Double(gasPrice),
              let usdStr = ethUsdPrice,
              let usd = Double(usdStr) else { return nil }
        let costEth = gwei * 21000.0 * 1e9 / 1e18
        let costUsd = costEth * usd
        return String(format: "$%.4f", costUsd)
    }

    private var transactionJSON: String {
        var tx: [String: Any] = [
            "from": "0x\(key.publicKey.suffix(40))",
            "to": toAddress,
            "value": value,
            "nonce": nonce,
            "gasLimit": gasLimit,
            "gasPrice": "\(gasPrice) gwei",
            "maxPriorityFeePerGas": "\(maxPriorityFee) gwei",
            "chainId": chainId,
            "network": networkName
        ]
        if !data.isEmpty {
            tx["data"] = data
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: tx, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Network indicator + block + ETH price (tap to change network)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle()
                                .fill(ethereumRPC == "mainnet" ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(networkName)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                            Text("Chain \(chainId)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            if let block = lastBlock {
                                Text("Block \(block)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            if let balance = ethBalance {
                                HStack(spacing: 4) {
                                    Text("BAL")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text("\(balance) ETH")
                                        .font(.system(size: 9, design: .monospaced))
                                }
                            }
                            if let price = ethUsdPrice {
                                HStack(spacing: 4) {
                                    Text("ETH")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text("$\(price)")
                                        .font(.system(size: 9, design: .monospaced))
                                }
                            }
                            Spacer()
                            if isLoadingGas {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.gray.opacity(0.1))
                    .cornerRadius(4)
                    .contentShape(Rectangle())
                    .onTapGesture { showNetworkSelector = true }

                    // Gas oracle summary
                    if let oracle = gasOracle {
                        HStack(spacing: 0) {
                            gasLevel(label: "SAFE", gwei: oracle.safeGasPrice, color: .green)
                            gasLevel(label: "STANDARD", gwei: oracle.proposeGasPrice, color: .blue)
                            gasLevel(label: "FAST", gwei: oracle.fastGasPrice, color: .orange)
                        }
                        .padding(6)
                        .background(.gray.opacity(0.05))
                        .cornerRadius(4)
                        .onTapGesture { showGasSheet = true }

                        if let costUsd = txCostUsd {
                            HStack {
                                Text("EST. TX COST")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(costUsd)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                            }
                        }
                    }

                    txField(label: "NONCE", text: $nonce, placeholder: "0")
                    txField(label: "TO ADDRESS", text: $toAddress, placeholder: "0x...")
                    txField(label: "VALUE (ETH)", text: $value, placeholder: "0.01", usdNote: ethToUsd(value))
                    txField(label: "GAS LIMIT", text: $gasLimit, placeholder: "21000", usdNote: gweiToUsd(gasPrice, gasUnits: Double(gasLimit) ?? 21000))
                    txField(label: "GAS PRICE (GWEI)", text: $gasPrice, placeholder: "20", usdNote: gweiToUsd(gasPrice, gasUnits: 1))
                    txField(label: "PRIORITY FEE (GWEI)", text: $maxPriorityFee, placeholder: "1.5", usdNote: gweiToUsd(maxPriorityFee, gasUnits: 1))
                    txField(label: "DATA (HEX)", text: $data, placeholder: "0x (optional)")

                    // Chain ID (read-only)
                    HStack {
                        Text("CHAIN ID")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(chainId)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .padding(8)
                    .background(.gray.opacity(0.1))
                    .cornerRadius(4)

                    Spacer().frame(height: 8)

                    // Preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transaction Preview")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(transactionJSON)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.gray.opacity(0.05))
                            .cornerRadius(4)
                    }

                    HStack(spacing: 8) {
                        Button(action: {
                            #if os(iOS)
                            UIPasteboard.general.string = transactionJSON
                            #endif
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { showShareSheet = true }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(toAddress.isEmpty)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Sign Transaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: fetchLiveData) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                }
            }
            .onAppear { fetchLiveData() }
            #if os(iOS)
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [transactionJSON])
            }
            #endif
            .sheet(isPresented: $showGasSheet) {
                gasTrackerSheet
            }
            .sheet(isPresented: $showNetworkSelector) {
                NetworkSelectorSheet(selectedNetwork: $ethereumRPC, onChanged: {
                    // Clear stale data and refresh for new network
                    gasOracle = nil
                    ethBalance = nil
                    ethUsdPrice = nil
                    lastBlock = nil
                    fetchLiveData()
                })
            }
            .alert("Network Error", isPresented: Binding(get: { apiErrorMessage != nil }, set: { if !$0 { apiErrorMessage = nil } })) {
                Button("Change Network") { showNetworkSelector = true }
                Button("OK", role: .cancel) { apiErrorMessage = nil }
            } message: {
                Text(apiErrorMessage ?? "")
            }
        }
    }

    private func fetchLiveData() {
        let service = EtherscanService(apiKey: etherscanAPIKey, chain: ethereumRPC)
        isLoadingGas = true
        apiErrorMessage = nil
        Task {
            var errors: [String] = []

            do {
                let oracle = try await service.fetchGasOracle()
                gasOracle = oracle
                lastBlock = oracle.lastBlock
                if gasPrice == "20" {
                    gasPrice = oracle.proposeGasPrice
                }
            } catch {
                errors.append(error.localizedDescription)
            }

            do {
                let price = try await service.fetchEthPrice()
                ethUsdPrice = price.ethusd
            } catch {
                // Price errors are less critical, only add if unique
                let msg = error.localizedDescription
                if !errors.contains(msg) { errors.append(msg) }
            }

            do {
                let bal = try await service.fetchBalance(address: key.publicKey.suffix(40).description)
                ethBalance = bal
            } catch {
                let msg = error.localizedDescription
                if !errors.contains(msg) { errors.append(msg) }
            }

            isLoadingGas = false

            if !errors.isEmpty {
                apiErrorMessage = errors.joined(separator: "\n")
            }
        }
    }

    private func ethToUsd(_ ethStr: String) -> String? {
        guard let eth = Double(ethStr),
              let usdStr = ethUsdPrice,
              let usd = Double(usdStr) else { return nil }
        let costUsd = eth * usd
        return String(format: "$%.4f", costUsd)
    }

    private func gweiToUsd(_ gweiStr: String, gasUnits: Double = 21000) -> String? {
        guard let gwei = Double(gweiStr),
              let usdStr = ethUsdPrice,
              let usd = Double(usdStr) else { return nil }
        let costEth = gwei * gasUnits * 1e9 / 1e18
        let costUsd = costEth * usd
        return String(format: "$%.4f", costUsd)
    }

    private func formatGwei(_ value: String) -> String {
        guard let v = Double(value) else { return value }
        if v >= 1 { return String(format: "%.1f", v) }
        return String(format: "%.3f", v)
    }

    @ViewBuilder
    private func gasLevel(label: String, gwei: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(formatGwei(gwei))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Text("gwei")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.secondary)
            if let usd = gweiToUsd(gwei) {
                Text(usd)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var gasTrackerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let oracle = gasOracle {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GAS TRACKER")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))

                        HStack(spacing: 0) {
                            gasLevel(label: "SAFE", gwei: oracle.safeGasPrice, color: .green)
                            gasLevel(label: "STANDARD", gwei: oracle.proposeGasPrice, color: .blue)
                            gasLevel(label: "FAST", gwei: oracle.fastGasPrice, color: .orange)
                        }
                        .padding(12)
                        .background(.gray.opacity(0.05))
                        .cornerRadius(6)

                        VStack(alignment: .leading, spacing: 4) {
                            infoRow("Base Fee", oracle.suggestBaseFee + " gwei")
                            infoRow("Block", oracle.lastBlock)
                            infoRow("Gas Used Ratio", oracle.gasUsedRatio)
                            if let price = ethUsdPrice {
                                infoRow("ETH/USD", "$\(price)")
                            }
                            if let balance = ethBalance {
                                infoRow("Balance", "\(balance) ETH")
                            }
                        }
                        .padding(12)
                        .background(.gray.opacity(0.05))
                        .cornerRadius(6)
                    }
                    .padding(16)

                    Spacer()

                    HStack(spacing: 8) {
                        Button("Use Safe (\(oracle.safeGasPrice))") {
                            gasPrice = oracle.safeGasPrice
                            showGasSheet = false
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 10, design: .monospaced))

                        Button("Use Standard (\(oracle.proposeGasPrice))") {
                            gasPrice = oracle.proposeGasPrice
                            showGasSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.system(size: 10, design: .monospaced))

                        Button("Use Fast (\(oracle.fastGasPrice))") {
                            gasPrice = oracle.fastGasPrice
                            showGasSheet = false
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 10, design: .monospaced))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading gas data...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Gas Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showGasSheet = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        #if os(iOS)
                        shareGasInfo()
                        #endif
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, design: .monospaced))
        }
    }

    #if os(iOS)
    private func shareGasInfo() {
        guard let oracle = gasOracle else { return }
        var text = """
        Gas Tracker — \(networkName)
        ============================

        Safe:     \(oracle.safeGasPrice) gwei
        Standard: \(oracle.proposeGasPrice) gwei
        Fast:     \(oracle.fastGasPrice) gwei
        Base Fee: \(oracle.suggestBaseFee) gwei
        Block:    \(oracle.lastBlock)
        """
        if let price = ethUsdPrice {
            text += "\nETH/USD:  $\(price)"
        }
        if let balance = ethBalance {
            text += "\nBalance:  \(balance) ETH"
        }
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            if let popover = av.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            topVC.present(av, animated: true)
        }
    }
    #endif

    @ViewBuilder
    private func txField(label: String, text: Binding<String>, placeholder: String, usdNote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                if let usd = usdNote {
                    Spacer()
                    Text(usd)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            TextField(placeholder, text: text)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .background(.gray.opacity(0.1))
                .cornerRadius(4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

// MARK: - Network Selector Sheet

struct NetworkSelectorSheet: View {
    @Binding var selectedNetwork: String
    var onChanged: () -> Void
    @Environment(\.dismiss) var dismiss

    private struct NetworkOption: Identifiable {
        let id: String  // AppStorage tag
        let name: String
        let chainId: String
        let isTestnet: Bool
        let gasOracleSupported: Bool
        let nativeCurrency: String
    }

    private let networks: [NetworkOption] = [
        NetworkOption(id: "mainnet", name: "Ethereum Mainnet", chainId: "1", isTestnet: false, gasOracleSupported: true, nativeCurrency: "ETH"),
        NetworkOption(id: "base", name: "Base", chainId: "8453", isTestnet: false, gasOracleSupported: true, nativeCurrency: "ETH"),
        NetworkOption(id: "arbitrum", name: "Arbitrum One", chainId: "42161", isTestnet: false, gasOracleSupported: true, nativeCurrency: "ETH"),
        NetworkOption(id: "optimism", name: "Optimism", chainId: "10", isTestnet: false, gasOracleSupported: true, nativeCurrency: "ETH"),
        NetworkOption(id: "polygon", name: "Polygon", chainId: "137", isTestnet: false, gasOracleSupported: true, nativeCurrency: "MATIC"),
        NetworkOption(id: "bsc", name: "BNB Smart Chain", chainId: "56", isTestnet: false, gasOracleSupported: true, nativeCurrency: "BNB"),
        NetworkOption(id: "sepolia", name: "Sepolia Testnet", chainId: "11155111", isTestnet: true, gasOracleSupported: true, nativeCurrency: "ETH"),
        NetworkOption(id: "hoodi", name: "Hoodi Testnet", chainId: "560048", isTestnet: true, gasOracleSupported: false, nativeCurrency: "ETH"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Mainnets")) {
                    ForEach(networks.filter { !$0.isTestnet }) { net in
                        networkRow(net)
                    }
                }
                Section(header: Text("Testnets")) {
                    ForEach(networks.filter { $0.isTestnet }) { net in
                        networkRow(net)
                    }
                }
            }
            .navigationTitle("Select Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func networkRow(_ net: NetworkOption) -> some View {
        Button(action: {
            #if os(iOS)
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            #endif
            selectedNetwork = net.id
            dismiss()
            onChanged()
        }) {
            HStack(spacing: 10) {
                Circle()
                    .fill(net.isTestnet ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(net.name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                    HStack(spacing: 8) {
                        Text("Chain \(net.chainId)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(net.nativeCurrency)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !net.gasOracleSupported {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                }

                if selectedNetwork == net.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
            }
        }
    }
}
