import Foundation
#if os(iOS)
import UIKit
#endif

/// API client for the CB-MPC key server
/// Thread-safe actor that handles device registration, session creation, and health checks
actor ServerAPIClient {
    let baseURL: URL
    private let session: URLSession
    private var authToken: String?
    private var deviceId: String?

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)

        // Load stored credentials
        let urlString = baseURL.absoluteString
        self.authToken = ServerAuthKeychain.loadToken(for: urlString)
        self.deviceId = ServerAuthKeychain.loadDeviceId(for: urlString)
    }

    var isAuthenticated: Bool { authToken != nil }
    var currentDeviceId: String? { deviceId }

    // MARK: - Health Check

    struct HealthResponse: Decodable {
        let status: String
        let version: String?
    }

    func health() async throws -> HealthResponse {
        let url = baseURL.appendingPathComponent("health")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CBMPCError.serverUnreachable
        }
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    // MARK: - Device Registration

    struct RegisterResponse: Decodable {
        let device_id: String
        let token: String
        let registered_at: Int
    }

    func register(deviceName: String, deviceType: String, publicKey: String) async throws -> RegisterResponse {
        let url = baseURL.appendingPathComponent("devices/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "device_name": deviceName,
            "device_type": deviceType,
            "public_key": publicKey
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CBMPCError.serverUnreachable
        }

        guard http.statusCode == 201 else {
            if http.statusCode == 401 {
                throw CBMPCError.authFailed
            }
            let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let msg = errorBody?["error"] as? String ?? "Registration failed (HTTP \(http.statusCode))"
            throw CBMPCError.transportError(msg)
        }

        let result = try JSONDecoder().decode(RegisterResponse.self, from: data)

        // Store credentials in Keychain
        let urlString = baseURL.absoluteString
        _ = ServerAuthKeychain.storeToken(result.token, for: urlString)
        _ = ServerAuthKeychain.storeDeviceId(result.device_id, for: urlString)

        self.authToken = result.token
        self.deviceId = result.device_id

        return result
    }

    // MARK: - DKG Session

    struct DKGSessionResponse: Decodable {
        let session_id: String
        let status: String
        let curve_code: Int
        let ws_url: String
    }

    func createDKGSession(curveCode: Int = 714) async throws -> DKGSessionResponse {
        guard let token = authToken, let devId = deviceId else {
            throw CBMPCError.authFailed
        }

        let url = baseURL.appendingPathComponent("sessions/dkg")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "device_id": devId,
            "curve_code": curveCode
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateAuthResponse(response, data: data)

        return try JSONDecoder().decode(DKGSessionResponse.self, from: data)
    }

    // MARK: - Sign Session

    struct SignSessionResponse: Decodable {
        let session_id: String
        let status: String
        let public_key: String
        let message_hash: String
        let ws_url: String
    }

    func createSignSession(
        sessionId: String,
        publicKey: String,
        messageHash: String
    ) async throws -> SignSessionResponse {
        guard let token = authToken, let devId = deviceId else {
            throw CBMPCError.authFailed
        }

        let url = baseURL.appendingPathComponent("sessions/\(sessionId)/sign")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "public_key": publicKey,
            "message_hash": messageHash,
            "device_id": devId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateAuthResponse(response, data: data)

        return try JSONDecoder().decode(SignSessionResponse.self, from: data)
    }

    // MARK: - Key Vault

    struct KeyVaultResponse: Decodable {
        let public_key: String
        let curve_code: Int?
        let server_share: String?  // base64-encoded server share
        let participant_devices: [String]?
        let created_at: Int?
        let last_used_at: Int?
        let sign_count: Int?
    }

    func getKey(publicKey: String) async throws -> KeyVaultResponse {
        guard let token = authToken else { throw CBMPCError.authFailed }

        let url = baseURL.appendingPathComponent("keys/\(publicKey)")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateAuthResponse(response, data: data)

        return try JSONDecoder().decode(KeyVaultResponse.self, from: data)
    }

    func storeKeyShare(
        publicKey: String,
        curveCode: Int,
        serverShare: Data,
        participantDevices: [String]
    ) async throws {
        guard let token = authToken else { throw CBMPCError.authFailed }

        let url = baseURL.appendingPathComponent("keys/\(publicKey)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "curve_code": curveCode,
            "server_share": serverShare.base64EncodedString(),
            "participant_devices": participantDevices
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateAuthResponse(response, data: data)
    }

    // MARK: - WebSocket URL Builder

    /// Build full WebSocket URL for a session, including auth params
    func webSocketURL(path: String) -> URL? {
        guard let token = authToken, let devId = deviceId else { return nil }

        var components = URLComponents()
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "device_id", value: devId),
            URLQueryItem(name: "token", value: token)
        ]

        return components.url
    }

    // MARK: - Helpers

    private func validateAuthResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CBMPCError.serverUnreachable
        }
        switch http.statusCode {
        case 200, 201:
            return
        case 401:
            throw CBMPCError.authFailed
        case 408, 504:
            throw CBMPCError.sessionTimeout
        default:
            let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let msg = errorBody?["error"] as? String ?? "Server error (HTTP \(http.statusCode))"
            throw CBMPCError.transportError(msg)
        }
    }
}
