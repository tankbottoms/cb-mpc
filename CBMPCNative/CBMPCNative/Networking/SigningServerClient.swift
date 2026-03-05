import Foundation

actor SigningServerClient {
    static let shared = SigningServerClient()

    struct SubmitPayload: Codable {
        let nonce: String
        let publicKey: String
        let signature: String
        let message: String
        let timestamp: String
    }

    struct SubmitResponse: Codable {
        let success: Bool
        let message: String?
    }

    func submit(
        nonce: String,
        publicKey: String,
        signature: String,
        message: String,
        serverURL: String
    ) async throws {
        guard let url = URL(string: serverURL) else {
            throw SubmitError.invalidURL
        }

        let payload = SubmitPayload(
            nonce: nonce,
            publicKey: publicKey,
            signature: signature,
            message: message,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SubmitError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SubmitError.serverError(statusCode: httpResponse.statusCode)
        }

        _ = try JSONDecoder().decode(SubmitResponse.self, from: data)
    }

    enum SubmitError: LocalizedError {
        case invalidURL
        case invalidResponse
        case serverError(statusCode: Int)
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid server URL"
            case .invalidResponse:
                return "Invalid server response"
            case .serverError(let code):
                return "Server returned error: \(code)"
            case .decodingError(let error):
                return "Failed to parse response: \(error.localizedDescription)"
            }
        }
    }
}
