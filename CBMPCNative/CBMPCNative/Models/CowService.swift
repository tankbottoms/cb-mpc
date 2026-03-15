import Foundation

// MARK: - CoW Protocol Service

/// Service for interacting with the CoW Protocol (formerly CoW Swap) API.
/// Supports mainnet, gnosis, and arbitrum chains.
/// API docs: https://docs.cow.fi/cow-protocol/reference/apis
struct CowService {

    // MARK: - Chain Configuration

    /// CoW Protocol settlement contract address (same on all supported chains)
    static let settlementContract = "0x9008D19f58AAbD9eD0D60971565AA8510560ab41"

    /// Supported chains and their API path segments
    private static let supportedChains: [String: (path: String, chainId: Int)] = [
        "mainnet":  (path: "mainnet",  chainId: 1),
        "gnosis":   (path: "gnosis",   chainId: 100),
        "arbitrum": (path: "arbitrum_one", chainId: 42161),
    ]

    private static func baseURL(chain: String) throws -> String {
        guard let config = supportedChains[chain] else {
            throw CowError.apiError("Unsupported chain: \(chain). CoW Protocol supports: mainnet, gnosis, arbitrum")
        }
        return "https://api.cow.fi/\(config.path)/api/v1"
    }

    private static func chainId(for chain: String) -> Int {
        supportedChains[chain]?.chainId ?? 1
    }

    // MARK: - Data Models

    struct CowQuoteRequest: Codable {
        let sellToken: String
        let buyToken: String
        let sellAmountBeforeFee: String
        let from: String
        let kind: String
        let appData: String

        init(
            sellToken: String,
            buyToken: String,
            sellAmountBeforeFee: String,
            from: String,
            kind: String = "sell",
            appData: String = "0x0000000000000000000000000000000000000000000000000000000000000000"
        ) {
            self.sellToken = sellToken
            self.buyToken = buyToken
            self.sellAmountBeforeFee = sellAmountBeforeFee
            self.from = from
            self.kind = kind
            self.appData = appData
        }
    }

    struct CowQuoteResponse: Codable {
        let quote: CowOrderQuote
        let id: Int?
    }

    struct CowOrderQuote: Codable {
        let sellToken: String
        let buyToken: String
        let sellAmount: String
        let buyAmount: String
        let feeAmount: String
        let kind: String
        let validTo: Int
        let receiver: String?
    }

    struct CowOrderSubmission: Codable {
        let sellToken: String
        let buyToken: String
        let sellAmount: String
        let buyAmount: String
        let validTo: Int
        let feeAmount: String
        let kind: String
        let receiver: String
        let from: String
        let appData: String
        let signature: String
        let signingScheme: String

        init(
            sellToken: String,
            buyToken: String,
            sellAmount: String,
            buyAmount: String,
            validTo: Int,
            feeAmount: String,
            kind: String,
            receiver: String,
            from: String,
            appData: String,
            signature: String,
            signingScheme: String = "eip712"
        ) {
            self.sellToken = sellToken
            self.buyToken = buyToken
            self.sellAmount = sellAmount
            self.buyAmount = buyAmount
            self.validTo = validTo
            self.feeAmount = feeAmount
            self.kind = kind
            self.receiver = receiver
            self.from = from
            self.appData = appData
            self.signature = signature
            self.signingScheme = signingScheme
        }
    }

    struct CowOrderResponse: Codable {
        let uid: String
    }

    struct CowOrderStatus: Codable {
        /// One of: "presignaturePending", "open", "fulfilled", "cancelled", "expired"
        let status: String
        let executedSellAmount: String?
        let executedBuyAmount: String?
    }

    // MARK: - Errors

    enum CowError: LocalizedError {
        case invalidURL
        case apiError(String)
        case decodingError

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid CoW Protocol URL"
            case .apiError(let msg): return "CoW API: \(msg)"
            case .decodingError: return "Failed to decode CoW API response"
            }
        }
    }

    // MARK: - API Methods

    /// Request a quote for a swap.
    /// - Parameters:
    ///   - sellToken: Address of the token to sell
    ///   - buyToken: Address of the token to buy
    ///   - amount: Sell amount before fee (in token's smallest unit, as a decimal string)
    ///   - from: Address of the order sender
    ///   - chain: Chain name ("mainnet", "gnosis", or "arbitrum")
    /// - Returns: The quote response containing order parameters and fee
    static func getQuote(
        sellToken: String,
        buyToken: String,
        amount: String,
        from: String,
        chain: String = "mainnet"
    ) async throws -> CowQuoteResponse {
        let base = try baseURL(chain: chain)
        guard let url = URL(string: "\(base)/quote") else {
            throw CowError.invalidURL
        }

        let quoteRequest = CowQuoteRequest(
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmountBeforeFee: amount,
            from: from
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(quoteRequest)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CowError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        do {
            return try JSONDecoder().decode(CowQuoteResponse.self, from: data)
        } catch {
            throw CowError.decodingError
        }
    }

    /// Submit a signed order to the CoW Protocol.
    /// - Parameters:
    ///   - order: The fully populated and signed order submission
    ///   - chain: Chain name ("mainnet", "gnosis", or "arbitrum")
    /// - Returns: The order UID string
    static func submitOrder(
        order: CowOrderSubmission,
        chain: String = "mainnet"
    ) async throws -> String {
        let base = try baseURL(chain: chain)
        guard let url = URL(string: "\(base)/orders") else {
            throw CowError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(order)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 201 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CowError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        // The response is a bare JSON string (quoted UID), e.g. "0xabc123..."
        guard let uid = try? JSONDecoder().decode(String.self, from: data) else {
            // Fallback: try trimming quotes manually
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if trimmed.isEmpty {
                throw CowError.decodingError
            }
            return trimmed
        }

        return uid
    }

    /// Get the status of an existing order.
    /// - Parameters:
    ///   - uid: The order UID returned from submitOrder
    ///   - chain: Chain name ("mainnet", "gnosis", or "arbitrum")
    /// - Returns: The current order status
    static func getOrderStatus(
        uid: String,
        chain: String = "mainnet"
    ) async throws -> CowOrderStatus {
        let base = try baseURL(chain: chain)
        let encodedUID = uid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? uid
        guard let url = URL(string: "\(base)/orders/\(encodedUID)") else {
            throw CowError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CowError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        do {
            return try JSONDecoder().decode(CowOrderStatus.self, from: data)
        } catch {
            throw CowError.decodingError
        }
    }

    // MARK: - EIP-712 Order Hash

    /// Compute the EIP-712 typed data hash for a CoW Protocol order.
    /// This hash is what must be signed (via MPC or otherwise) to authorize the order.
    ///
    /// - Parameters:
    ///   - order: The order submission containing all order fields
    ///   - chainId: The numeric chain ID (1 = mainnet, 100 = gnosis, 42161 = arbitrum)
    /// - Returns: 32-byte Keccak256 hash ready for signing
    static func orderHash(order: CowOrderSubmission, chainId: Int) -> Data {
        let types: [String: [EIP712Signer.TypeField]] = [
            "EIP712Domain": [
                EIP712Signer.TypeField(name: "name", type: "string"),
                EIP712Signer.TypeField(name: "version", type: "string"),
                EIP712Signer.TypeField(name: "chainId", type: "uint256"),
                EIP712Signer.TypeField(name: "verifyingContract", type: "address"),
            ],
            "Order": [
                EIP712Signer.TypeField(name: "sellToken", type: "address"),
                EIP712Signer.TypeField(name: "buyToken", type: "address"),
                EIP712Signer.TypeField(name: "receiver", type: "address"),
                EIP712Signer.TypeField(name: "sellAmount", type: "uint256"),
                EIP712Signer.TypeField(name: "buyAmount", type: "uint256"),
                EIP712Signer.TypeField(name: "validTo", type: "uint32"),
                EIP712Signer.TypeField(name: "appData", type: "bytes32"),
                EIP712Signer.TypeField(name: "feeAmount", type: "uint256"),
                EIP712Signer.TypeField(name: "kind", type: "string"),
                EIP712Signer.TypeField(name: "partiallyFillable", type: "bool"),
                EIP712Signer.TypeField(name: "sellTokenBalance", type: "string"),
                EIP712Signer.TypeField(name: "buyTokenBalance", type: "string"),
            ],
        ]

        let domain: [String: Any] = [
            "name": "Gnosis Protocol",
            "version": "v2",
            "chainId": chainId,
            "verifyingContract": settlementContract,
        ]

        let message: [String: Any] = [
            "sellToken": order.sellToken,
            "buyToken": order.buyToken,
            "receiver": order.receiver,
            "sellAmount": order.sellAmount,
            "buyAmount": order.buyAmount,
            "validTo": order.validTo,
            "appData": order.appData,
            "feeAmount": order.feeAmount,
            "kind": order.kind,
            "partiallyFillable": false,
            "sellTokenBalance": "erc20",
            "buyTokenBalance": "erc20",
        ]

        let typedData = EIP712Signer.TypedData(
            types: types,
            primaryType: "Order",
            domain: domain,
            message: message
        )

        return EIP712Signer.hashTypedData(typedData)
    }

    /// Convenience: compute order hash using chain name instead of numeric chain ID.
    static func orderHash(order: CowOrderSubmission, chain: String = "mainnet") -> Data {
        return orderHash(order: order, chainId: chainId(for: chain))
    }
}
