import Foundation

struct EtherscanService {

    struct GasOracle: Codable {
        let lastBlock: String
        let safeGasPrice: String
        let proposeGasPrice: String
        let fastGasPrice: String
        let suggestBaseFee: String
        let gasUsedRatio: String

        enum CodingKeys: String, CodingKey {
            case lastBlock = "LastBlock"
            case safeGasPrice = "SafeGasPrice"
            case proposeGasPrice = "ProposeGasPrice"
            case fastGasPrice = "FastGasPrice"
            case suggestBaseFee = "suggestBaseFee"
            case gasUsedRatio = "gasUsedRatio"
        }
    }

    struct EthPrice: Codable {
        let ethbtc: String
        let ethbtcTimestamp: String
        let ethusd: String
        let ethusdTimestamp: String

        enum CodingKeys: String, CodingKey {
            case ethbtc
            case ethbtcTimestamp = "ethbtc_timestamp"
            case ethusd
            case ethusdTimestamp = "ethusd_timestamp"
        }
    }

    struct APIResponse<T: Codable>: Codable {
        let status: String
        let message: String
        let result: T
    }

    struct BalanceResponse: Codable {
        let status: String
        let message: String
        let result: String
    }

    struct ErrorResponse: Codable {
        let status: String
        let message: String
        let result: String
    }

    enum APIError: LocalizedError {
        case apiMessage(String)

        var errorDescription: String? {
            switch self {
            case .apiMessage(let msg): return msg
            }
        }
    }

    private static let v2BaseURL = "https://api.etherscan.io/v2/api"

    private let apiKey: String
    private let chainId: String

    init(apiKey: String, chain: String = "mainnet") {
        self.apiKey = apiKey
        self.chainId = EtherscanService.chainId(for: chain)
    }

    static func chainId(for chain: String) -> String {
        switch chain {
        case "mainnet": return "1"
        case "sepolia": return "11155111"
        case "hoodi": return "560048"
        case "base": return "8453"
        case "arbitrum": return "42161"
        case "optimism": return "10"
        case "polygon": return "137"
        case "bsc": return "56"
        default: return "1"
        }
    }

    private func buildURL(module: String, action: String, extra: [String: String] = [:]) -> URL {
        var params = "chainid=\(chainId)&module=\(module)&action=\(action)&apikey=\(apiKey)"
        for (k, v) in extra {
            params += "&\(k)=\(v)"
        }
        return URL(string: "\(Self.v2BaseURL)?\(params)")!
    }

    // MARK: - Gas Oracle

    private func checkForError(_ data: Data) throws {
        if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           err.status == "0" {
            throw APIError.apiMessage(err.result)
        }
    }

    func fetchGasOracle() async throws -> GasOracle {
        let url = buildURL(module: "gastracker", action: "gasoracle")
        let (data, _) = try await URLSession.shared.data(from: url)
        try checkForError(data)
        let response = try JSONDecoder().decode(APIResponse<GasOracle>.self, from: data)
        return response.result
    }

    // MARK: - ETH Price

    func fetchEthPrice() async throws -> EthPrice {
        let url = buildURL(module: "stats", action: "ethprice")
        let (data, _) = try await URLSession.shared.data(from: url)
        try checkForError(data)
        let response = try JSONDecoder().decode(APIResponse<EthPrice>.self, from: data)
        return response.result
    }

    // MARK: - Balance

    func fetchBalance(address: String) async throws -> String {
        let addr = address.hasPrefix("0x") ? address : "0x\(address)"
        let url = buildURL(module: "account", action: "balance", extra: ["address": addr, "tag": "latest"])
        let (data, _) = try await URLSession.shared.data(from: url)
        try checkForError(data)
        let response = try JSONDecoder().decode(BalanceResponse.self, from: data)
        // Result is in wei -- convert to ETH
        if let wei = Double(response.result) {
            let eth = wei / 1e18
            if eth == 0 {
                return "0"
            } else if eth < 0.0001 {
                return String(format: "%.8f", eth)
            } else {
                return String(format: "%.6f", eth)
            }
        }
        return response.result
    }

    // MARK: - Gas Estimate for Transfer

    func estimateGasCost(gasPrice: String) -> String {
        // Standard ETH transfer = 21000 gas
        // gasPrice is in Gwei
        if let gwei = Double(gasPrice) {
            let costWei = gwei * 21000.0 * 1e9
            let costEth = costWei / 1e18
            return String(format: "%.6f", costEth)
        }
        return "—"
    }

    // MARK: - Transaction History

    struct Transaction: Codable {
        let blockNumber: String
        let timeStamp: String
        let hash: String
        let from: String
        let to: String
        let value: String
        let gas: String
        let gasUsed: String
        let gasPrice: String
        let isError: String
        let functionName: String?
        let contractAddress: String?

        var ethValue: String {
            if let wei = Double(value) {
                let eth = wei / 1e18
                if eth == 0 { return "0" }
                else if eth < 0.0001 { return String(format: "%.8f", eth) }
                else { return String(format: "%.6f", eth) }
            }
            return value
        }

        var gasCostETH: String {
            if let used = Double(gasUsed), let price = Double(gasPrice) {
                let costEth = (used * price) / 1e18
                return String(format: "%.6f", costEth)
            }
            return "—"
        }

        var date: Date {
            Date(timeIntervalSince1970: Double(timeStamp) ?? 0)
        }
    }

    func fetchTransactionHistory(address: String, page: Int = 1, offset: Int = 25) async throws -> [Transaction] {
        let addr = address.hasPrefix("0x") ? address : "0x\(address)"
        let url = buildURL(
            module: "account",
            action: "txlist",
            extra: [
                "address": addr,
                "startblock": "0",
                "endblock": "99999999",
                "page": "\(page)",
                "offset": "\(offset)",
                "sort": "desc",
            ]
        )
        let (data, _) = try await URLSession.shared.data(from: url)
        try checkForError(data)
        let response = try JSONDecoder().decode(APIResponse<[Transaction]>.self, from: data)
        return response.result
    }

    // MARK: - Chain Support Test

    /// Test whether the Etherscan API works for a given chain with the current API key.
    /// Returns .free if it works on free tier, .paid if it requires a paid key, .unsupported otherwise.
    static func testChainSupport(apiKey: String, chain: String) async -> ChainSupportStatus {
        let service = EtherscanService(apiKey: apiKey, chain: chain)
        let url = service.buildURL(module: "gastracker", action: "gasoracle")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return .unsupported }
            if httpResponse.statusCode == 200 {
                if let json = try? JSONDecoder().decode(APIResponse<GasOracle>.self, from: data),
                   !json.result.lastBlock.isEmpty {
                    return .free
                }
                // Check for "requires paid" error
                if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    if err.result.lowercased().contains("api key") ||
                       err.result.lowercased().contains("api pro") ||
                       err.result.lowercased().contains("premium") ||
                       err.message == "NOTOK" {
                        return .paid
                    }
                }
            }
            return .unsupported
        } catch {
            return .unsupported
        }
    }

    enum ChainSupportStatus: String, Codable {
        case free       // Works on free tier
        case paid       // Requires paid API key
        case unsupported // Not supported at all
    }
}

// MARK: - RPC Service

struct RPCService {

    /// Build the full RPC URL for a given network, provider, and Infura key.
    static func endpoint(network: String, provider: String, infuraKey: String) -> String {
        if network == "mainnet" {
            return freeMainnetURL(provider: provider)
        }
        return infuraURL(network: network, key: infuraKey)
    }

    static let freeMainnetProviders: [(key: String, name: String, url: String)] = [
        ("buidlguidl", "BuidlGuidl", "https://mainnet.rpc.buidlguidl.com"),
        ("publicnode", "PublicNode", "https://ethereum.publicnode.com"),
        ("1rpc", "1RPC", "https://1rpc.io/eth"),
        ("llamarpc", "LlamaRPC", "https://eth.llamarpc.com"),
        ("drpc", "dRPC", "https://eth.drpc.org"),
        ("merkle", "Merkle", "https://eth.merkle.io"),
        ("flashbots", "Flashbots", "https://rpc.flashbots.net/fast"),
        ("nodies", "Nodies", "https://ethereum-public.nodies.app"),
        ("tenderly", "Tenderly", "https://mainnet.gateway.tenderly.co"),
    ]

    private static func freeMainnetURL(provider: String) -> String {
        freeMainnetProviders.first(where: { $0.key == provider })?.url
            ?? "https://mainnet.rpc.buidlguidl.com"
    }

    private static func infuraURL(network: String, key: String) -> String {
        let base: String
        switch network {
        case "sepolia": base = "https://sepolia.infura.io"
        case "base": base = "https://base-mainnet.infura.io"
        case "arbitrum": base = "https://arbitrum-mainnet.infura.io"
        case "optimism": base = "https://optimism-mainnet.infura.io"
        case "polygon": base = "https://polygon-mainnet.infura.io"
        case "bsc": base = "https://bsc-mainnet.infura.io"
        default: base = "https://hoodi.infura.io"
        }
        return "\(base)/v3/\(key)"
    }

    /// Send eth_blockNumber to an RPC endpoint and return (blockNumber, latencyMs).
    static func testConnection(url: String) async throws -> (blockNumber: String, latencyMs: Int) {
        guard let rpcURL = URL(string: url) else {
            throw RPCError.invalidURL
        }
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}"#.utf8)
        request.timeoutInterval = 10

        let start = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RPCError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        struct RPCResponse: Codable {
            let result: String?
            let error: RPCErrorDetail?
        }
        struct RPCErrorDetail: Codable {
            let message: String
        }

        let rpcResponse = try JSONDecoder().decode(RPCResponse.self, from: data)
        if let err = rpcResponse.error {
            throw RPCError.rpcError(err.message)
        }
        guard let hexBlock = rpcResponse.result else {
            throw RPCError.noResult
        }

        // Convert hex block number to decimal
        let hex = hexBlock.hasPrefix("0x") ? String(hexBlock.dropFirst(2)) : hexBlock
        let blockNum = UInt64(hex, radix: 16) ?? 0
        return (blockNumber: String(blockNum), latencyMs: elapsed)
    }

    // MARK: - JSON-RPC Call Helper

    private static func jsonRPC(url: String, method: String, params: [Any]) async throws -> Any {
        guard let rpcURL = URL(string: url) else { throw RPCError.invalidURL }
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params, "id": 1]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RPCError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RPCError.noResult
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw RPCError.rpcError(message)
        }
        guard let result = json["result"] else {
            throw RPCError.noResult
        }
        return result
    }

    // MARK: - Transaction Nonce

    /// Get the pending transaction count (nonce) for an address.
    static func getTransactionCount(url: String, address: String) async throws -> UInt64 {
        let addr = address.hasPrefix("0x") ? address : "0x\(address)"
        let result = try await jsonRPC(url: url, method: "eth_getTransactionCount", params: [addr, "pending"])
        guard let hex = result as? String else { throw RPCError.noResult }
        return hexToUInt64(hex)
    }

    // MARK: - Gas Estimation

    /// Estimate gas for a transaction.
    static func estimateGas(url: String, from: String, to: String, value: String, data: String = "0x") async throws -> UInt64 {
        var tx: [String: String] = ["from": from, "to": to, "value": value]
        if data != "0x" && !data.isEmpty { tx["data"] = data }
        let result = try await jsonRPC(url: url, method: "eth_estimateGas", params: [tx])
        guard let hex = result as? String else { throw RPCError.noResult }
        return hexToUInt64(hex)
    }

    // MARK: - Broadcast Raw Transaction

    /// Broadcast a signed raw transaction. Returns the transaction hash.
    static func sendRawTransaction(url: String, signedTx: String) async throws -> String {
        let tx = signedTx.hasPrefix("0x") ? signedTx : "0x\(signedTx)"
        let result = try await jsonRPC(url: url, method: "eth_sendRawTransaction", params: [tx])
        guard let txHash = result as? String else { throw RPCError.noResult }
        return txHash
    }

    // MARK: - Gas Price

    /// Get current gas price in wei (hex string).
    static func gasPrice(url: String) async throws -> UInt64 {
        let result = try await jsonRPC(url: url, method: "eth_gasPrice", params: [])
        guard let hex = result as? String else { throw RPCError.noResult }
        return hexToUInt64(hex)
    }

    // MARK: - Helpers

    private static func hexToUInt64(_ hex: String) -> UInt64 {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        return UInt64(clean, radix: 16) ?? 0
    }

    enum RPCError: LocalizedError {
        case invalidURL
        case httpError(Int)
        case rpcError(String)
        case noResult

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid RPC URL"
            case .httpError(let code): return "HTTP \(code)"
            case .rpcError(let msg): return msg
            case .noResult: return "No result from RPC"
            }
        }
    }
}
