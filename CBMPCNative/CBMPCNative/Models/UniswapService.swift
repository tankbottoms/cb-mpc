import Foundation

// MARK: - Uniswap Trading API Service

struct UniswapService {

    private static let baseURL = "https://trade-api.gateway.uniswap.org/v1"
    private static let apiKey = "06FtHN6MJYP6vCYV4ae4-2nd3jR6ze8Ee033o0tnv9A"

    // MARK: - Common Token Addresses

    static let ETH  = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
    static let WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    static let USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    static let USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
    static let DAI  = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
    static let WBTC = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"

    // MARK: - Data Models

    struct SwapQuote: Codable {
        let tokenIn: String
        let tokenOut: String
        let amount: String
        let swapper: String
        let chainId: Int
    }

    struct QuoteResponse {
        let quote: QuoteDetails
        let permitData: PermitData?
        let methodParameters: MethodParams?
    }

    struct QuoteDetails {
        let amountOut: String
        let gasEstimate: String
        let priceImpact: String?
        let route: String?
    }

    struct PermitData {
        /// Raw JSON dictionaries for EIP-712 signing.
        /// Pass to EIP712Signer.parseTypedData(from:) for structured hashing.
        let domain: [String: Any]
        let types: [String: Any]
        let values: [String: Any]
    }

    struct MethodParams: Codable {
        let to: String
        let calldata: String
        let value: String
    }

    struct OrderRequest: Codable {
        let orderId: String
        let signature: String
    }

    struct OrderResponse: Codable {
        let orderId: String
    }

    struct OrderStatus: Codable {
        let status: String
        let txHash: String?
    }

    // MARK: - Errors

    enum UniswapError: LocalizedError {
        case invalidURL
        case apiError(String)
        case decodingError

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Uniswap API URL"
            case .apiError(let msg): return msg
            case .decodingError: return "Failed to decode Uniswap API response"
            }
        }
    }

    // MARK: - API Methods

    /// Request a swap quote from the Uniswap Trading API.
    static func getQuote(
        tokenIn: String,
        tokenOut: String,
        amount: String,
        swapper: String,
        chainId: Int
    ) async throws -> QuoteResponse {
        guard let url = URL(string: "\(baseURL)/quote") else {
            throw UniswapError.invalidURL
        }

        let body = SwapQuote(
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amount: amount,
            swapper: swapper,
            chainId: chainId
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPResponse(response, data: data)

        return try parseQuoteResponse(data)
    }

    /// Submit a signed order to the Uniswap Trading API.
    static func submitOrder(orderId: String, signature: String) async throws -> OrderResponse {
        guard let url = URL(string: "\(baseURL)/order") else {
            throw UniswapError.invalidURL
        }

        let body = OrderRequest(orderId: orderId, signature: signature)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPResponse(response, data: data)

        guard let orderResponse = try? JSONDecoder().decode(OrderResponse.self, from: data) else {
            throw UniswapError.decodingError
        }
        return orderResponse
    }

    /// Check the status of an existing order.
    static func getOrderStatus(orderId: String) async throws -> OrderStatus {
        guard let url = URL(string: "\(baseURL)/order/\(orderId)") else {
            throw UniswapError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPResponse(response, data: data)

        guard let status = try? JSONDecoder().decode(OrderStatus.self, from: data) else {
            throw UniswapError.decodingError
        }
        return status
    }

    // MARK: - Internal Helpers

    private static func checkHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UniswapError.apiError("Invalid response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            // Try to extract error message from response body
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMsg = json["errorCode"] as? String ?? json["detail"] as? String ?? json["message"] as? String {
                throw UniswapError.apiError("HTTP \(httpResponse.statusCode): \(errorMsg)")
            }
            throw UniswapError.apiError("HTTP \(httpResponse.statusCode)")
        }
    }

    /// Parse the quote response manually to handle dynamic PermitData fields.
    private static func parseQuoteResponse(_ data: Data) throws -> QuoteResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UniswapError.decodingError
        }

        // Parse quote details
        guard let quoteDict = json["quote"] as? [String: Any],
              let amountOut = quoteDict["amountOut"] as? String,
              let gasEstimate = quoteDict["gasEstimate"] as? String else {
            throw UniswapError.decodingError
        }
        let quoteDetails = QuoteDetails(
            amountOut: amountOut,
            gasEstimate: gasEstimate,
            priceImpact: quoteDict["priceImpact"] as? String,
            route: quoteDict["route"] as? String
        )

        // Parse permitData (dynamic JSON — kept as [String: Any] for EIP-712 signing)
        var permitData: PermitData?
        if let permitDict = json["permitData"] as? [String: Any],
           let domain = permitDict["domain"] as? [String: Any],
           let types = permitDict["types"] as? [String: Any],
           let values = permitDict["values"] as? [String: Any] {
            permitData = PermitData(domain: domain, types: types, values: values)
        }

        // Parse methodParameters (simple Codable struct)
        var methodParams: MethodParams?
        if let methodDict = json["methodParameters"] as? [String: Any] {
            if let methodData = try? JSONSerialization.data(withJSONObject: methodDict),
               let decoded = try? JSONDecoder().decode(MethodParams.self, from: methodData) {
                methodParams = decoded
            }
        }

        return QuoteResponse(
            quote: quoteDetails,
            permitData: permitData,
            methodParameters: methodParams
        )
    }
}
