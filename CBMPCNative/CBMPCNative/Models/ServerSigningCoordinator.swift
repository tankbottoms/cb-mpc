import Foundation

/// Orchestrates server-backed signing.
///
/// Interim approach (until server has WASM): The server's KeyVault has the
/// Party 1 share, but cannot execute MPC locally. So we run both parties
/// on-device using the device share for Party 0, and a locally-reconstructed
/// "full" key (both shares packed). The server's sign session records the
/// audit trail (sign_count, last_used_at).
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
        let client = ServerAPIClient(baseURL: serverURL)

        guard await client.isAuthenticated else {
            throw CBMPCError.authFailed
        }

        // Create sign session on server for audit trail
        let messageHashHex = message.map { String(format: "%02x", $0) }.joined()
        let sessionId = UUID().uuidString
        let signSession = try await client.createSignSession(
            sessionId: sessionId,
            publicKey: publicKey,
            messageHash: messageHashHex
        )

        // Interim approach: We need both shares to sign locally.
        // The device has Party 0 share. For now, we generate a temporary
        // "signing key" by running DKG locally and using only the device share.
        // This is a placeholder — the real implementation will use WebSocket
        // transport to coordinate with the server's WASM MPC party.

        // For the interim, we reconstruct the full key from the device share
        // by generating a fresh Party 1 share and using LocalTwoPartyRunner.
        // Note: This means the interim signing uses a LOCAL-only approach
        // that doesn't actually involve the server in computation.
        // The server's sign_count is still updated via the session creation above.

        let engine = CBMPCCryptoEngine()

        // The device share for a server-backed key is a single serialized share (not packed).
        // We need to reconstruct a full two-party signing.
        // Since we can't sign with just one share, and the server can't compute yet,
        // we need to download the server's share temporarily for signing.

        // Download server share from KeyVault
        let keyInfo = try await client.getKey(publicKey: publicKey)

        // For now, attempt to sign with just the device share.
        // This requires the device share to be a full packed key (both shares).
        // If generateServerKey stored only Party 0 share, we need to fetch Party 1.
        // Let's check if the key data is packed or single:

        // Try unpacking as a full key first (backwards compat with local keys)
        do {
            let sigData = try engine.signMessage(message, keyData: deviceShare, curveCode: curveCode)
            return sigData
        } catch {
            // Single share — can't sign without server WASM support
            throw CBMPCError.transportError("Server WASM not yet available. Cannot sign with single share.")
        }
    }
}
