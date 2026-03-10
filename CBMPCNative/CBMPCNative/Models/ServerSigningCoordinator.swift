import Foundation
import CryptoKit

/// Orchestrates server-backed signing.
///
/// Interim approach (until server has WASM): Download the server's Party 1
/// share from KeyVault, pack both shares locally as
/// [4-byte k0 length][k0 bytes][k1 bytes], then sign with CBMPCCryptoEngine.
///
/// The server's sign session records the audit trail (sign_count, last_used_at).
///
/// When server WASM lands, this will use WebSocket transport to sign with
/// the server holding its own share.
class ServerSigningCoordinator {

    /// Sign a message using server-backed key (interim: both parties local)
    static func sign(
        message: Data,
        deviceShare: Data,
        curveCode: Int,
        serverURL: URL,
        publicKey: String
    ) async throws -> Data {
        let startTime = Date()
        print("[ServerSign] START — server=\(serverURL.host ?? "?"), pubKey=\(String(publicKey.prefix(16)))...")

        let client = ServerAPIClient(baseURL: serverURL)

        guard await client.isAuthenticated else {
            print("[ServerSign] ERROR: Not authenticated")
            throw CBMPCError.authFailed
        }

        // Create sign session on server for audit trail
        let messageHashHex = message.map { String(format: "%02x", $0) }.joined()
        let sessionId = UUID().uuidString
        print("[ServerSign] Creating sign session \(String(sessionId.prefix(8)))...")
        _ = try await client.createSignSession(
            sessionId: sessionId,
            publicKey: publicKey,
            messageHash: messageHashHex
        )

        // Download server share from KeyVault
        print("[ServerSign] Downloading server share from KeyVault...")
        let keyInfo = try await client.getKey(publicKey: publicKey)
        guard let serverShareB64 = keyInfo.server_share,
              let serverShare = Data(base64Encoded: serverShareB64) else {
            print("[ServerSign] ERROR: Server did not return key share (server_share=\(keyInfo.server_share == nil ? "nil" : "present but invalid"))")
            throw CBMPCError.transportError("Server did not return key share")
        }
        print("[ServerSign] Server share downloaded: \(serverShare.count) bytes")

        // Pack shares: [4-byte k0 length][k0 bytes][k1 bytes]
        var packed = Data()
        var k0Len = UInt32(deviceShare.count).littleEndian
        packed.append(Data(bytes: &k0Len, count: 4))
        packed.append(deviceShare)
        packed.append(serverShare)
        print("[ServerSign] Packed key: device=\(deviceShare.count) + server=\(serverShare.count) = \(packed.count) bytes")

        // SHA-256 pre-hash if message is not already 32 bytes (raw message from caller)
        let hashData: Data
        if message.count == 32 {
            hashData = message  // Already hashed by caller
        } else {
            let digest = SHA256.hash(data: message)
            hashData = Data(digest)
        }

        let engine = CBMPCCryptoEngine()
        let sigData = try engine.signMessage(hashData, keyData: packed, curveCode: curveCode)
        let duration = Date().timeIntervalSince(startTime)
        print("[ServerSign] DONE in \(String(format: "%.2f", duration))s — signature=\(sigData.count) bytes")
        return sigData
    }
}
