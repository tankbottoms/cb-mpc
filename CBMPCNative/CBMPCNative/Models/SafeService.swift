import Foundation

// MARK: - Safe Transaction Service API

/// Gnosis Safe Transaction Service client.
/// Interacts with the Safe{Global} backend API for multisig wallet operations.
struct SafeService {

    // MARK: - Chain Configuration

    static let apiBaseByChain: [String: String] = [
        "mainnet":  "https://safe-transaction-mainnet.safe.global/api",
        "polygon":  "https://safe-transaction-polygon.safe.global/api",
        "arbitrum": "https://safe-transaction-arbitrum.safe.global/api",
        "optimism": "https://safe-transaction-optimism.safe.global/api",
        "base":     "https://safe-transaction-base.safe.global/api",
        "bsc":      "https://safe-transaction-bsc.safe.global/api",
    ]

    // MARK: - Errors

    enum SafeError: Error, LocalizedError {
        case invalidURL
        case apiError(String)
        case notFound

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .apiError(let message):
                return "Safe API error: \(message)"
            case .notFound:
                return "Resource not found"
            }
        }
    }

    // MARK: - Data Models

    struct SafeInfo: Codable {
        let address: String
        let nonce: Int
        let threshold: Int
        let owners: [String]
        let version: String?
    }

    struct SafeTransaction: Codable {
        let safe: String
        let to: String
        let value: String
        let data: String
        let operation: Int          // 0 = call, 1 = delegatecall
        let safeTxGas: String
        let baseGas: String
        let gasPrice: String
        let gasToken: String
        let refundReceiver: String
        let nonce: Int
    }

    struct PendingTransaction: Codable {
        let safeTxHash: String
        let to: String
        let value: String
        let data: String?
        let confirmations: [Confirmation]
        let isExecuted: Bool
        let submissionDate: String
    }

    struct Confirmation: Codable {
        let owner: String
        let signature: String
        let submissionDate: String
    }

    /// Wrapper for the paginated list response from the Safe API.
    private struct PaginatedResponse<T: Codable>: Codable {
        let count: Int
        let results: [T]
    }

    // MARK: - API Methods

    /// Fetch Safe metadata (owners, threshold, nonce, version).
    static func getSafeInfo(address: String, chain: String) async throws -> SafeInfo {
        let base = try apiBase(for: chain)
        let url = try buildURL("\(base)/v1/safes/\(address)/")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(SafeInfo.self, from: data)
    }

    /// Fetch unexecuted (pending) multisig transactions for a Safe.
    static func getPendingTransactions(address: String, chain: String) async throws -> [PendingTransaction] {
        let base = try apiBase(for: chain)
        let url = try buildURL("\(base)/v1/safes/\(address)/multisig-transactions/?executed=false")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response, data: data)
        let page = try JSONDecoder().decode(PaginatedResponse<PendingTransaction>.self, from: data)
        return page.results
    }

    /// Propose a new multisig transaction to the Safe Transaction Service.
    static func proposeTransaction(
        safe address: String,
        tx: SafeTransaction,
        signature: String,
        senderAddress: String,
        chain: String
    ) async throws {
        let base = try apiBase(for: chain)
        let url = try buildURL("\(base)/v1/safes/\(address)/multisig-transactions/")

        var body: [String: Any] = [
            "safe":           tx.safe,
            "to":             tx.to,
            "value":          tx.value,
            "data":           tx.data,
            "operation":      tx.operation,
            "safeTxGas":      tx.safeTxGas,
            "baseGas":        tx.baseGas,
            "gasPrice":       tx.gasPrice,
            "gasToken":       tx.gasToken,
            "refundReceiver": tx.refundReceiver,
            "nonce":          tx.nonce,
            "signature":      signature,
            "sender":         senderAddress,
        ]
        // contractTransactionHash is required by the API
        let safeTxHash = computeSafeTxHash(safe: address, tx: tx, chainId: chainId(for: chain))
        body["contractTransactionHash"] = "0x" + safeTxHash.map { String(format: "%02x", $0) }.joined()

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    /// Submit a confirmation (co-signature) for an existing pending transaction.
    static func confirmTransaction(
        safeTxHash: String,
        signature: String,
        chain: String
    ) async throws {
        let base = try apiBase(for: chain)
        let url = try buildURL("\(base)/v1/multisig-transactions/\(safeTxHash)/confirmations/")

        let body: [String: Any] = ["signature": signature]
        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    // MARK: - EIP-712 Safe Transaction Hash

    /// Compute the EIP-712 typed-data hash for a Safe transaction.
    /// This is the hash that each owner signs to approve the transaction.
    static func computeSafeTxHash(safe address: String, tx: SafeTransaction, chainId: Int) -> Data {
        let types: [String: [EIP712Signer.TypeField]] = [
            "EIP712Domain": [
                EIP712Signer.TypeField(name: "verifyingContract", type: "address"),
                EIP712Signer.TypeField(name: "chainId", type: "uint256"),
            ],
            "SafeTx": [
                EIP712Signer.TypeField(name: "to", type: "address"),
                EIP712Signer.TypeField(name: "value", type: "uint256"),
                EIP712Signer.TypeField(name: "data", type: "bytes"),
                EIP712Signer.TypeField(name: "operation", type: "uint8"),
                EIP712Signer.TypeField(name: "safeTxGas", type: "uint256"),
                EIP712Signer.TypeField(name: "baseGas", type: "uint256"),
                EIP712Signer.TypeField(name: "gasPrice", type: "uint256"),
                EIP712Signer.TypeField(name: "gasToken", type: "address"),
                EIP712Signer.TypeField(name: "refundReceiver", type: "address"),
                EIP712Signer.TypeField(name: "nonce", type: "uint256"),
            ],
        ]

        let domain: [String: Any] = [
            "verifyingContract": address,
            "chainId": chainId,
        ]

        let message: [String: Any] = [
            "to":             tx.to,
            "value":          tx.value,
            "data":           tx.data,
            "operation":      tx.operation,
            "safeTxGas":      tx.safeTxGas,
            "baseGas":        tx.baseGas,
            "gasPrice":       tx.gasPrice,
            "gasToken":       tx.gasToken,
            "refundReceiver": tx.refundReceiver,
            "nonce":          tx.nonce,
        ]

        let typedData = EIP712Signer.TypedData(
            types: types,
            primaryType: "SafeTx",
            domain: domain,
            message: message
        )

        return EIP712Signer.hashTypedData(typedData)
    }

    // MARK: - Helpers

    private static func apiBase(for chain: String) throws -> String {
        guard let base = apiBaseByChain[chain] else {
            throw SafeError.apiError("Unsupported chain: \(chain)")
        }
        return base
    }

    private static func buildURL(_ string: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw SafeError.invalidURL
        }
        return url
    }

    private static func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SafeError.apiError("Non-HTTP response")
        }
        switch http.statusCode {
        case 200...299:
            return
        case 404:
            throw SafeError.notFound
        default:
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw SafeError.apiError("HTTP \(http.statusCode): \(body)")
        }
    }

    /// Map chain name to EIP-155 chain ID.
    private static func chainId(for chain: String) -> Int {
        switch chain {
        case "mainnet":  return 1
        case "polygon":  return 137
        case "arbitrum": return 42161
        case "optimism": return 10
        case "base":     return 8453
        case "bsc":      return 56
        default:         return 1
        }
    }
}
