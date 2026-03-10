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
}
