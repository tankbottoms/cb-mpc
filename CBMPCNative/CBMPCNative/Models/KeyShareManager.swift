import Foundation
import Security

actor KeyShareManager {
    static let shared = KeyShareManager()

    enum KeyShareError: LocalizedError {
        case storeFailed(String)
        case retrieveFailed(String)
        case notFound(String)
        case invalidFormat(String)

        var errorDescription: String? {
            switch self {
            case .storeFailed(let msg): return "Failed to store share: \(msg)"
            case .retrieveFailed(let msg): return "Failed to retrieve share: \(msg)"
            case .notFound(let msg): return "Share not found: \(msg)"
            case .invalidFormat(let msg): return "Invalid share format: \(msg)"
            }
        }
    }

    private let keychainQueue = DispatchQueue(label: "cb-mpc.keyshare.keychain")

    func storeShare(
        shareBytes: Data,
        keyId: UUID,
        partyId: Int,
        ceremonyType: String,
        publicKey: String = ""
    ) async throws -> KeyShare {
        let shareId = "cb-mpc.share.\(keyId.uuidString).\(partyId)"

        // Remove existing if present
        try? await deleteShare(shareId: shareId)

        let keyShareMetadata = KeyShare(
            id: shareId,
            keyId: keyId,
            partyId: partyId,
            ceremonyType: ceremonyType,
            createdAt: Date(),
            publicKey: publicKey
        )

        return try await withCheckedThrowingContinuation { continuation in
            keychainQueue.async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: shareId,
                    kSecAttrService as String: "cb-mpc.keyshare",
                    kSecValueData as String: shareBytes,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                ]

                let status = SecItemAdd(query as CFDictionary, nil)
                if status == errSecSuccess {
                    continuation.resume(returning: keyShareMetadata)
                } else {
                    continuation.resume(throwing: KeyShareError.storeFailed("Status: \(status)"))
                }
            }
        }
    }

    func retrieveShare(shareId: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            keychainQueue.async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: shareId,
                    kSecAttrService as String: "cb-mpc.keyshare",
                    kSecReturnData as String: true,
                ]

                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)

                if status == errSecSuccess, let data = result as? Data {
                    continuation.resume(returning: data)
                } else if status == errSecItemNotFound {
                    continuation.resume(throwing: KeyShareError.notFound(shareId))
                } else {
                    continuation.resume(throwing: KeyShareError.retrieveFailed("Status: \(status)"))
                }
            }
        }
    }

    func deleteShare(shareId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            keychainQueue.async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: shareId,
                    kSecAttrService as String: "cb-mpc.keyshare",
                ]

                let status = SecItemDelete(query as CFDictionary)
                if status == errSecSuccess || status == errSecItemNotFound {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: KeyShareError.storeFailed("Delete failed: \(status)"))
                }
            }
        }
    }

    func listShares(for keyId: UUID) async throws -> [KeyShare] {
        return []  // Future: query keychain for all matching shares
    }
}
