import SwiftUI

enum TransactionMode: String, CaseIterable {
    case send = "Send"
    case swap = "Swap"
    case contract = "Contract"
    case safe = "Safe"
    case history = "History"
}

struct TransactionsTabView: View {
    @EnvironmentObject var keyStore: KeyStore
    @AppStorage("ethereumRPC") private var ethereumRPC = "mainnet"
    @AppStorage("rpcProvider") private var rpcProvider = "buidlguidl"
    @AppStorage("infuraAPIKey") private var infuraAPIKey = "65980db64d52417abbda13b49e356d97"
    @AppStorage("etherscanAPIKey") private var etherscanAPIKey = "UWD3H7R1R6SXRUSW9R7SXYX3HUNQYC75W1"

    @State private var mode: TransactionMode = .send
    @State private var selectedKeyId: UUID?

    private var selectedKey: ManagedKey? {
        guard let id = selectedKeyId else { return keyStore.keys.first }
        return keyStore.keys.first(where: { $0.id == id })
    }

    private var rpcURL: String {
        RPCService.endpoint(network: ethereumRPC, provider: rpcProvider, infuraKey: infuraAPIKey)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode selector
                Picker("Mode", selection: $mode) {
                    ForEach(TransactionMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Key selector
                if keyStore.keys.count > 1 {
                    HStack {
                        Text("From")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        Picker("Key", selection: $selectedKeyId) {
                            ForEach(keyStore.keys) { key in
                                Text("0x\(key.shortAddress)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .tag(Optional(key.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }

                // Content
                switch mode {
                case .send:
                    if let key = selectedKey {
                        SendETHView(
                            key: key,
                            rpcURL: rpcURL,
                            ethereumRPC: ethereumRPC,
                            etherscanAPIKey: etherscanAPIKey
                        )
                    } else {
                        noKeysView
                    }
                case .swap:
                    if let key = selectedKey {
                        SwapView(
                            key: key,
                            rpcURL: rpcURL,
                            ethereumRPC: ethereumRPC,
                            etherscanAPIKey: etherscanAPIKey
                        )
                    } else {
                        noKeysView
                    }
                case .contract:
                    if let key = selectedKey {
                        ContractCallView(
                            key: key,
                            rpcURL: rpcURL,
                            ethereumRPC: ethereumRPC,
                            etherscanAPIKey: etherscanAPIKey
                        )
                    } else {
                        noKeysView
                    }
                case .safe:
                    if let key = selectedKey {
                        SafeManagementView(
                            key: key,
                            rpcURL: rpcURL,
                            ethereumRPC: ethereumRPC
                        )
                    } else {
                        noKeysView
                    }
                case .history:
                    if let key = selectedKey {
                        TransactionHistoryView(
                            key: key,
                            ethereumRPC: ethereumRPC,
                            etherscanAPIKey: etherscanAPIKey
                        )
                    } else {
                        noKeysView
                    }
                }
            }
            .navigationTitle("Transactions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                if selectedKeyId == nil {
                    selectedKeyId = keyStore.keys.first?.id
                }
            }
        }
    }

    private var noKeysView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "key.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No keys available")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.secondary)
            Text("Create or import a key first")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Send ETH View

struct SendETHView: View {
    let key: ManagedKey
    let rpcURL: String
    let ethereumRPC: String
    let etherscanAPIKey: String

    @StateObject private var addressBook = AddressBook()

    @State private var toAddress = ""
    @State private var amount = ""
    @State private var gasLimit: UInt64 = 21000
    @State private var gasPriceGwei = ""
    @State private var nonce: UInt64?
    @State private var balance: String?
    @State private var ethUsdPrice: String?

    @State private var isLoadingInfo = false
    @State private var isBroadcasting = false
    @State private var broadcastResult: String?
    @State private var broadcastError: String?
    @State private var showAddressPicker = false
    @State private var showSignSheet = false

    private var fromAddress: String {
        "0x\(key.publicKey.suffix(40))"
    }

    private var chainId: String {
        EtherscanService.chainId(for: ethereumRPC)
    }

    private var estimatedCostEth: String? {
        guard let gwei = Double(gasPriceGwei) else { return nil }
        let cost = gwei * Double(gasLimit) * 1e9 / 1e18
        return String(format: "%.6f", cost)
    }

    private var estimatedCostUsd: String? {
        guard let costEth = estimatedCostEth,
              let eth = Double(costEth),
              let usdStr = ethUsdPrice,
              let usd = Double(usdStr) else { return nil }
        return String(format: "$%.4f", eth * usd)
    }

    private var isValidAddress: Bool {
        toAddress.hasPrefix("0x") && toAddress.count == 42
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Account info
                accountInfoSection

                // To address
                toAddressSection

                // Amount
                amountSection

                // Gas settings
                gasSection

                // Transaction summary
                if isValidAddress && !amount.isEmpty {
                    summarySection
                }

                // Broadcast result
                if let txHash = broadcastResult {
                    broadcastResultSection(txHash: txHash)
                }

                if let err = broadcastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                        Text(err)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    .padding(10)
                    .background(.red.opacity(0.05))
                    .cornerRadius(6)
                }

                // Actions
                actionButtons

                Spacer(minLength: 160)
            }
            .padding(16)
        }
        .onAppear { loadAccountInfo() }
        .sheet(isPresented: $showAddressPicker) {
            AddressPickerView(addressBook: addressBook) { entry in
                toAddress = entry.address
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSignSheet) {
            SignTransactionSheetView(key: key)
                .presentationDetents([.large])
        }
    }

    // MARK: - Sections

    private var accountInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("From")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                if isLoadingInfo {
                    ProgressView().controlSize(.mini)
                }
            }
            Text(fromAddress)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 12) {
                if let bal = balance {
                    Text("\(bal) ETH")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                if let usd = ethUsdPrice {
                    Text("ETH $\(usd)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                if let n = nonce {
                    Text("Nonce: \(n)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(.blue.opacity(0.05))
        .cornerRadius(6)
    }

    private var toAddressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("To")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { showAddressPicker = true }) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            TextField("0x...", text: $toAddress)
                .font(.system(size: 12, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(8)
                .background(.gray.opacity(0.1))
                .cornerRadius(4)

            if !toAddress.isEmpty && !isValidAddress {
                Text("Invalid address format")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Amount (ETH)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            HStack {
                TextField("0.0", text: $amount)
                    .font(.system(size: 14, design: .monospaced))
                    .keyboardType(.decimalPad)
                    .padding(8)
                    .background(.gray.opacity(0.1))
                    .cornerRadius(4)

                if let bal = balance {
                    Button("Max") {
                        // Leave some for gas
                        if let balVal = Double(bal),
                           let costEth = estimatedCostEth,
                           let cost = Double(costEth) {
                            let maxVal = max(0, balVal - cost)
                            amount = String(format: "%.6f", maxVal)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .buttonStyle(.bordered)
                }
            }

            if let usd = ethUsdPrice, let amt = Double(amount) {
                if let usdVal = Double(usd) {
                    Text(String(format: "~ $%.2f", amt * usdVal))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var gasSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Gas")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Refresh") { loadGasPrice() }
                    .font(.system(size: 10, design: .monospaced))
                    .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Price (Gwei)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                    TextField("20", text: $gasPriceGwei)
                        .font(.system(size: 12, design: .monospaced))
                        .keyboardType(.decimalPad)
                        .padding(6)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Limit")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("\(gasLimit)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.gray.opacity(0.05))
                        .cornerRadius(4)
                }
            }
            if let cost = estimatedCostEth {
                HStack {
                    Text("Est. fee: \(cost) ETH")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let usd = estimatedCostUsd {
                        Text("(\(usd))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TRANSACTION SUMMARY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                summaryRow("Chain", "\(networkName(ethereumRPC)) (ID: \(chainId))")
                summaryRow("To", toAddress)
                summaryRow("Value", "\(amount) ETH")
                summaryRow("Gas Price", "\(gasPriceGwei) Gwei")
                summaryRow("Gas Limit", "\(gasLimit)")
                if let n = nonce {
                    summaryRow("Nonce", "\(n)")
                }
            }
        }
        .padding(10)
        .background(.green.opacity(0.05))
        .cornerRadius(6)
    }

    private func broadcastResultSection(txHash: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                Text("Transaction Submitted")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            Text(txHash)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .textSelection(.enabled)

            let explorerBase = ethereumRPC == "mainnet" ? "https://etherscan.io" :
                ethereumRPC == "polygon" ? "https://polygonscan.com" :
                ethereumRPC == "arbitrum" ? "https://arbiscan.io" :
                ethereumRPC == "optimism" ? "https://optimistic.etherscan.io" :
                ethereumRPC == "base" ? "https://basescan.org" :
                ethereumRPC == "bsc" ? "https://bscscan.com" :
                "https://sepolia.etherscan.io"
            Link("View on Explorer", destination: URL(string: "\(explorerBase)/tx/\(txHash)")!)
                .font(.system(size: 11, design: .monospaced))
        }
        .padding(10)
        .background(.green.opacity(0.08))
        .cornerRadius(6)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: { showSignSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "signature")
                        .font(.system(size: 12))
                    Text("Sign & Build")
                        .font(.system(size: 13, design: .monospaced))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isValidAddress || amount.isEmpty)
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func networkName(_ network: String) -> String {
        switch network {
        case "mainnet": return "Ethereum"
        case "sepolia": return "Sepolia"
        case "base": return "Base"
        case "arbitrum": return "Arbitrum"
        case "optimism": return "Optimism"
        case "polygon": return "Polygon"
        case "bsc": return "BNB Chain"
        default: return network
        }
    }

    // MARK: - Data Loading

    private func loadAccountInfo() {
        isLoadingInfo = true
        Task {
            // Load balance, nonce, gas price, ETH price in parallel
            async let balanceResult = EtherscanService(apiKey: etherscanAPIKey, chain: ethereumRPC).fetchBalance(address: fromAddress)
            async let nonceResult = RPCService.getTransactionCount(url: rpcURL, address: fromAddress)
            async let gasPriceResult = RPCService.gasPrice(url: rpcURL)
            async let ethPriceResult = EtherscanService(apiKey: etherscanAPIKey, chain: ethereumRPC).fetchEthPrice()

            let bal = try? await balanceResult
            let n = try? await nonceResult
            let gp = try? await gasPriceResult
            let price = try? await ethPriceResult

            await MainActor.run {
                if let bal { balance = bal }
                if let n { nonce = n }
                if let gp {
                    let gwei = Double(gp) / 1e9
                    gasPriceGwei = String(format: "%.1f", gwei)
                }
                if let price { ethUsdPrice = price.ethusd }
                isLoadingInfo = false
            }
        }
    }

    private func loadGasPrice() {
        Task {
            if let gp = try? await RPCService.gasPrice(url: rpcURL) {
                await MainActor.run {
                    let gwei = Double(gp) / 1e9
                    gasPriceGwei = String(format: "%.1f", gwei)
                }
            }
        }
    }
}

// MARK: - Contract Call View

struct ContractCallView: View {
    let key: ManagedKey
    let rpcURL: String
    let ethereumRPC: String
    let etherscanAPIKey: String

    @State private var contractAddress = ""
    @State private var abiFunctions: [ContractService.ABIFunction] = []
    @State private var selectedFunction: ContractService.ABIFunction?
    @State private var functionInputs: [String] = []
    @State private var isLoadingABI = false
    @State private var abiError: String?

    private var isValidAddress: Bool {
        contractAddress.hasPrefix("0x") && contractAddress.count == 42
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Contract address
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contract Address")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    HStack {
                        TextField("0x...", text: $contractAddress)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)
                            .onChange(of: contractAddress) { newVal in
                                if newVal.count == 42 && newVal.hasPrefix("0x") {
                                    loadABI()
                                }
                            }

                        if isLoadingABI {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }

                if let err = abiError {
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red)
                }

                // Function list
                if !abiFunctions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FUNCTIONS (\(abiFunctions.count))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                        ForEach(abiFunctions, id: \.name) { fn in
                            Button(action: { selectFunction(fn) }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(fn.name)
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundColor(.primary)
                                        let params = fn.inputs.map { "\($0.type) \($0.name)" }.joined(separator: ", ")
                                        Text("(\(params))")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if let mutability = fn.stateMutability {
                                        Text(mutability)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(mutability == "view" || mutability == "pure" ? .green : .orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                (mutability == "view" || mutability == "pure" ? Color.green : Color.orange)
                                                    .opacity(0.1)
                                            )
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(8)
                                .background(selectedFunction?.name == fn.name ? .blue.opacity(0.05) : .clear)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Selected function inputs
                if let fn = selectedFunction, !fn.inputs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(fn.name) PARAMETERS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                        ForEach(Array(fn.inputs.enumerated()), id: \.offset) { idx, input in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(input.name) (\(input.type))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                TextField(input.type, text: binding(for: idx))
                                    .font(.system(size: 12, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(6)
                                    .background(.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(10)
                    .background(.blue.opacity(0.05))
                    .cornerRadius(6)
                }

                Spacer(minLength: 160)
            }
            .padding(16)
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        while functionInputs.count <= index {
            functionInputs.append("")
        }
        return Binding(
            get: { index < functionInputs.count ? functionInputs[index] : "" },
            set: { newValue in
                while functionInputs.count <= index { functionInputs.append("") }
                functionInputs[index] = newValue
            }
        )
    }

    private func selectFunction(_ fn: ContractService.ABIFunction) {
        selectedFunction = fn
        functionInputs = Array(repeating: "", count: fn.inputs.count)
    }

    private func loadABI() {
        guard isValidAddress else { return }
        isLoadingABI = true
        abiError = nil
        abiFunctions = []
        selectedFunction = nil

        // Check cache first
        if let cached = ContractService.loadCachedABI(chain: ethereumRPC, address: contractAddress) {
            abiFunctions = cached
            isLoadingABI = false
            return
        }

        Task {
            do {
                let fns = try await ContractService.fetchABI(
                    apiKey: etherscanAPIKey,
                    chain: ethereumRPC,
                    address: contractAddress
                )
                await MainActor.run {
                    abiFunctions = fns
                    isLoadingABI = false
                }
            } catch {
                await MainActor.run {
                    abiError = error.localizedDescription
                    isLoadingABI = false
                }
            }
        }
    }
}

// MARK: - Address Picker

struct AddressPickerView: View {
    @ObservedObject var addressBook: AddressBook
    let onSelect: (AddressEntry) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var newLabel = ""
    @State private var newAddress = ""
    @State private var showAddForm = false

    private var filteredEntries: [AddressEntry] {
        if searchText.isEmpty {
            return addressBook.sorted
        }
        return addressBook.search(searchText)
    }

    var body: some View {
        NavigationStack {
            List {
                if showAddForm {
                    Section("Add Address") {
                        TextField("Label", text: $newLabel)
                            .font(.system(size: 12, design: .monospaced))
                        TextField("0x...", text: $newAddress)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save") {
                            addressBook.add(label: newLabel, address: newAddress)
                            newLabel = ""
                            newAddress = ""
                            showAddForm = false
                        }
                        .disabled(newLabel.isEmpty || newAddress.count != 42)
                    }
                }

                Section("Addresses") {
                    if filteredEntries.isEmpty {
                        Text("No saved addresses")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    ForEach(filteredEntries) { entry in
                        Button(action: {
                            addressBook.markUsed(id: entry.id)
                            onSelect(entry)
                            dismiss()
                        }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.label)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.primary)
                                Text(entry.address)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                    .onDelete { indices in
                        for idx in indices {
                            let entry = filteredEntries[idx]
                            addressBook.remove(id: entry.id)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search addresses")
            .navigationTitle("Address Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddForm.toggle() }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - Swap View

struct SwapView: View {
    let key: ManagedKey
    let rpcURL: String
    let ethereumRPC: String
    let etherscanAPIKey: String

    enum SwapProvider: String, CaseIterable {
        case uniswap = "Uniswap"
        case cow = "CoW Protocol"
    }

    @State private var provider: SwapProvider = .uniswap
    @State private var sellToken = UniswapService.ETH
    @State private var buyToken = UniswapService.USDC
    @State private var sellAmount = ""
    @State private var quoteResult: String?
    @State private var priceImpact: String?
    @State private var gasEstimate: String?
    @State private var isQuoting = false
    @State private var quoteError: String?
    @State private var ethUsdPrice: String?

    private var fromAddress: String { "0x\(key.publicKey.suffix(40))" }
    private var chainId: Int { Int(EtherscanService.chainId(for: ethereumRPC)) ?? 1 }

    private struct TokenOption: Identifiable {
        let id: String // address
        let symbol: String
    }

    private let tokens: [TokenOption] = [
        TokenOption(id: UniswapService.ETH, symbol: "ETH"),
        TokenOption(id: UniswapService.USDC, symbol: "USDC"),
        TokenOption(id: UniswapService.USDT, symbol: "USDT"),
        TokenOption(id: UniswapService.DAI, symbol: "DAI"),
        TokenOption(id: UniswapService.WBTC, symbol: "WBTC"),
        TokenOption(id: UniswapService.WETH, symbol: "WETH"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Provider selector
                Picker("Provider", selection: $provider) {
                    ForEach(SwapProvider.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                if provider == .cow {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("Gasless + MEV Protected")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }

                // Token pair
                VStack(alignment: .leading, spacing: 4) {
                    Text("SELL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    HStack {
                        Picker("Token", selection: $sellToken) {
                            ForEach(tokens) { t in
                                Text(t.symbol).tag(t.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)

                        TextField("0.0", text: $sellAmount)
                            .font(.system(size: 14, design: .monospaced))
                            .keyboardType(.decimalPad)
                            .padding(8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                // Swap direction button
                HStack {
                    Spacer()
                    Button(action: {
                        let tmp = sellToken
                        sellToken = buyToken
                        buyToken = tmp
                    }) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 14))
                            .padding(8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("BUY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    HStack {
                        Picker("Token", selection: $buyToken) {
                            ForEach(tokens) { t in
                                Text(t.symbol).tag(t.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)

                        Text(quoteResult ?? "—")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(quoteResult != nil ? .primary : .secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.gray.opacity(0.05))
                            .cornerRadius(4)
                    }
                }

                // Quote details
                if let impact = priceImpact {
                    HStack {
                        Text("Price Impact")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(impact)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Double(impact.replacingOccurrences(of: "%", with: "")) ?? 0 > 3 ? .red : .green)
                    }
                }
                if let gas = gasEstimate {
                    HStack {
                        Text("Est. Gas")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(gas)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                if let err = quoteError {
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red)
                }

                // Get Quote button
                Button(action: getQuote) {
                    HStack(spacing: 8) {
                        if isQuoting {
                            ProgressView().controlSize(.mini)
                            Text("Getting Quote...")
                                .font(.system(size: 13, design: .monospaced))
                        } else {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 12))
                            Text("Get Quote")
                                .font(.system(size: 13, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sellAmount.isEmpty || isQuoting || sellToken == buyToken)

                Spacer(minLength: 160)
            }
            .padding(16)
        }
        .onAppear { loadEthPrice() }
    }

    private func getQuote() {
        isQuoting = true
        quoteError = nil
        quoteResult = nil
        priceImpact = nil
        gasEstimate = nil

        Task {
            do {
                if provider == .uniswap {
                    let quote = try await UniswapService.getQuote(
                        tokenIn: sellToken,
                        tokenOut: buyToken,
                        amount: sellAmount,
                        swapper: fromAddress,
                        chainId: chainId
                    )
                    await MainActor.run {
                        quoteResult = quote.quote.amountOut
                        priceImpact = quote.quote.priceImpact
                        gasEstimate = quote.quote.gasEstimate
                        isQuoting = false
                    }
                } else {
                    let quote = try await CowService.getQuote(
                        sellToken: sellToken,
                        buyToken: buyToken,
                        amount: sellAmount,
                        from: fromAddress,
                        chain: ethereumRPC
                    )
                    await MainActor.run {
                        quoteResult = quote.quote.buyAmount
                        gasEstimate = "Gasless"
                        isQuoting = false
                    }
                }
            } catch {
                await MainActor.run {
                    quoteError = error.localizedDescription
                    isQuoting = false
                }
            }
        }
    }

    private func loadEthPrice() {
        Task {
            if let price = try? await EtherscanService(apiKey: etherscanAPIKey, chain: ethereumRPC).fetchEthPrice() {
                await MainActor.run { ethUsdPrice = price.ethusd }
            }
        }
    }
}

// MARK: - Safe Management View

struct SafeManagementView: View {
    let key: ManagedKey
    let rpcURL: String
    let ethereumRPC: String

    @State private var safeAddress = ""
    @State private var safeInfo: SafeService.SafeInfo?
    @State private var pendingTxs: [SafeService.PendingTransaction] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isValidAddress: Bool {
        safeAddress.hasPrefix("0x") && safeAddress.count == 42
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Safe address input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Safe Address")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    HStack {
                        TextField("0x...", text: $safeAddress)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)

                        Button(action: loadSafe) {
                            if isLoading {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14))
                            }
                        }
                        .disabled(!isValidAddress || isLoading)
                    }
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red)
                }

                // Safe info display
                if let info = safeInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SAFE DETAILS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Threshold")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(info.threshold) of \(info.owners.count)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        if let version = info.version {
                            HStack {
                                Text("Version")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(version)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                        HStack {
                            Text("Nonce")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(info.nonce)")
                                .font(.system(size: 11, design: .monospaced))
                        }

                        Text("OWNERS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        ForEach(info.owners, id: \.self) { owner in
                            let isMe = owner.lowercased() == "0x\(key.publicKey.suffix(40))".lowercased()
                            HStack(spacing: 6) {
                                Image(systemName: isMe ? "person.fill.checkmark" : "person")
                                    .font(.system(size: 10))
                                    .foregroundColor(isMe ? .green : .secondary)
                                Text(owner)
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                if isMe {
                                    Text("You")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(.blue.opacity(0.05))
                    .cornerRadius(6)
                }

                // Pending transactions
                if !pendingTxs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PENDING TRANSACTIONS (\(pendingTxs.count))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                        ForEach(pendingTxs, id: \.safeTxHash) { tx in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("To: \(tx.to)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                    Spacer()
                                    Text("\(tx.confirmations.count) sig\(tx.confirmations.count == 1 ? "" : "s")")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                                Text("Value: \(tx.value) wei")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(tx.submissionDate)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(.orange.opacity(0.05))
                            .cornerRadius(4)
                        }
                    }
                }

                Spacer(minLength: 160)
            }
            .padding(16)
        }
    }

    private func loadSafe() {
        guard isValidAddress else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                async let infoResult = SafeService.getSafeInfo(address: safeAddress, chain: ethereumRPC)
                async let txsResult = SafeService.getPendingTransactions(address: safeAddress, chain: ethereumRPC)

                let info = try await infoResult
                let txs = try await txsResult

                await MainActor.run {
                    safeInfo = info
                    pendingTxs = txs
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Transaction History View

struct TransactionHistoryView: View {
    let key: ManagedKey
    let ethereumRPC: String
    let etherscanAPIKey: String

    @State private var transactions: [EtherscanService.Transaction] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var page = 1
    @State private var hasMore = true

    private var address: String {
        "0x\(key.publicKey.suffix(40))"
    }

    private var explorerBaseURL: String {
        switch ethereumRPC {
        case "sepolia": return "https://sepolia.etherscan.io"
        case "base": return "https://basescan.org"
        case "arbitrum": return "https://arbiscan.io"
        case "optimism": return "https://optimistic.etherscan.io"
        case "polygon": return "https://polygonscan.com"
        case "bsc": return "https://bscscan.com"
        default: return "https://etherscan.io"
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                // Address header
                HStack {
                    Text(address)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Spacer()
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .disabled(isLoading)
                }
                .padding(.bottom, 4)

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red)
                }

                if isLoading && transactions.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                }

                ForEach(transactions, id: \.hash) { tx in
                    txRow(tx)
                }

                if hasMore && !transactions.isEmpty {
                    Button("Load More") {
                        page += 1
                        loadHistory()
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .disabled(isLoading)
                }

                Spacer(minLength: 160)
            }
            .padding(16)
        }
        .onAppear { if transactions.isEmpty { loadHistory() } }
    }

    private func txRow(_ tx: EtherscanService.Transaction) -> some View {
        let isSent = tx.from.lowercased() == address.lowercased()
        let failed = tx.isError == "1"

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: isSent ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isSent ? .red : .green)

                Text(isSent ? "Sent" : "Received")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))

                if failed {
                    Text("FAILED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.red)
                        .cornerRadius(2)
                }

                Spacer()

                Text("\(isSent ? "-" : "+")\(tx.ethValue) ETH")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isSent ? .red : .green)
            }

            HStack {
                Text(isSent ? "To: \(tx.to)" : "From: \(tx.from)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            HStack {
                Text(tx.date, style: .relative)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Gas: \(tx.gasCostETH) ETH")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Tx hash link
            Link(destination: URL(string: "\(explorerBaseURL)/tx/\(tx.hash)")!) {
                Text(tx.hash.prefix(18) + "..." + tx.hash.suffix(6))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.blue)
            }
        }
        .padding(10)
        .background(failed ? .red.opacity(0.05) : (isSent ? .orange.opacity(0.03) : .green.opacity(0.03)))
        .cornerRadius(6)
    }

    private func refresh() {
        page = 1
        transactions = []
        hasMore = true
        loadHistory()
    }

    private func loadHistory() {
        isLoading = true
        errorMessage = nil
        let service = EtherscanService(apiKey: etherscanAPIKey, chain: ethereumRPC)

        Task {
            do {
                let txs = try await service.fetchTransactionHistory(address: address, page: page)
                await MainActor.run {
                    if page == 1 {
                        transactions = txs
                    } else {
                        transactions.append(contentsOf: txs)
                    }
                    hasMore = txs.count >= 25
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    TransactionsTabView()
        .environmentObject(KeyStore())
}
