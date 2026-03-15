import Foundation

struct ContractService {

    // MARK: - Models

    struct ABIParam: Codable {
        let name: String
        let type: String
        let indexed: Bool?
    }

    struct ABIFunction: Codable {
        let name: String
        let type: String
        let inputs: [ABIParam]
        let outputs: [ABIParam]
        let stateMutability: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            type = try container.decodeIfPresent(String.self, forKey: .type) ?? "function"
            inputs = try container.decodeIfPresent([ABIParam].self, forKey: .inputs) ?? []
            outputs = try container.decodeIfPresent([ABIParam].self, forKey: .outputs) ?? []
            stateMutability = try container.decodeIfPresent(String.self, forKey: .stateMutability)
        }

        init(name: String, type: String, inputs: [ABIParam], outputs: [ABIParam], stateMutability: String?) {
            self.name = name
            self.type = type
            self.inputs = inputs
            self.outputs = outputs
            self.stateMutability = stateMutability
        }
    }

    // MARK: - Errors

    enum ContractError: LocalizedError {
        case invalidURL
        case apiError(String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Etherscan URL"
            case .apiError(let msg): return msg
            case .parseError(let msg): return "ABI parse error: \(msg)"
            }
        }
    }

    // MARK: - API Response

    private struct ABIResponse: Codable {
        let status: String
        let message: String
        let result: String
    }

    // MARK: - Fetch ABI

    /// Fetch the contract ABI from Etherscan v2 API and cache it.
    /// Returns only entries with type "function".
    static func fetchABI(apiKey: String, chain: String, address: String) async throws -> [ABIFunction] {
        let chainId = EtherscanService.chainId(for: chain)
        let addr = address.hasPrefix("0x") ? address : "0x\(address)"
        let urlString = "https://api.etherscan.io/v2/api?chainid=\(chainId)&module=contract&action=getabi&address=\(addr)&apikey=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw ContractError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        let response = try JSONDecoder().decode(ABIResponse.self, from: data)

        guard response.status == "1" else {
            throw ContractError.apiError(response.result)
        }

        // result is a JSON string containing the ABI array
        guard let abiData = response.result.data(using: .utf8) else {
            throw ContractError.parseError("Could not convert result string to data")
        }

        let allEntries = try JSONDecoder().decode([ABIFunction].self, from: abiData)
        let functions = allEntries.filter { $0.type == "function" }

        // Cache the full ABI (all entries) in UserDefaults
        let cacheKey = "abi_\(chainId)_\(addr.lowercased())"
        if let encoded = try? JSONEncoder().encode(allEntries) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }

        return functions
    }

    // MARK: - Cache

    /// Load a previously cached ABI for the given chain and address.
    /// Returns only "function" type entries, or nil if no cache exists.
    static func loadCachedABI(chain: String, address: String) -> [ABIFunction]? {
        let chainId = EtherscanService.chainId(for: chain)
        let addr = address.hasPrefix("0x") ? address : "0x\(address)"
        let cacheKey = "abi_\(chainId)_\(addr.lowercased())"

        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }

        guard let allEntries = try? JSONDecoder().decode([ABIFunction].self, from: data) else {
            return nil
        }

        return allEntries.filter { $0.type == "function" }
    }

    /// Remove the cached ABI for a contract.
    static func clearCache(chain: String, address: String) {
        let chainId = EtherscanService.chainId(for: chain)
        let addr = address.hasPrefix("0x") ? address : "0x\(address)"
        let cacheKey = "abi_\(chainId)_\(addr.lowercased())"
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}