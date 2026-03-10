import Foundation
import Security

/// Keychain wrapper for storing/retrieving server auth tokens
/// Tokens are keyed by server URL using kSecClassGenericPassword
final class ServerAuthKeychain {
    private static let service = "xyz.atsignhandle.cb-mpc.server-auth"

    /// Store an auth token for a server URL
    static func storeToken(_ token: String, for serverURL: String) -> Bool {
        // Delete existing entry first
        deleteToken(for: serverURL)

        guard let tokenData = token.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverURL,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve the auth token for a server URL
    static func loadToken(for serverURL: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverURL,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete the auth token for a server URL
    @discardableResult
    static func deleteToken(for serverURL: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverURL
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Store the device ID received during registration
    static func storeDeviceId(_ deviceId: String, for serverURL: String) -> Bool {
        let key = "\(serverURL)::device_id"
        deleteToken(for: key) // reuse same pattern

        guard let data = deviceId.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve the device ID for a server URL
    static func loadDeviceId(for serverURL: String) -> String? {
        let key = "\(serverURL)::device_id"
        return loadToken(for: key)
    }
}
