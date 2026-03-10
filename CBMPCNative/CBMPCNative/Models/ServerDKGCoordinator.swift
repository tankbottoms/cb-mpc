import Foundation

/// Orchestrates server-backed DKG (Distributed Key Generation).
///
/// Interim approach (until server has WASM): Generate both shares locally via
/// LocalTwoPartyRunner, store Party 0 share on device, upload Party 1 share
/// to KeyVault via API. This gives the same key distribution result.
class ServerDKGCoordinator {

    struct DKGResult {
        let publicKey: Data          // Compressed SEC1 public key
        let deviceShare: Data        // Party 0 serialized share (device keeps this)
        let serverShare: Data        // Party 1 serialized share (uploaded to server)
        let sessionId: String
    }

    /// Generate a server-backed key using the interim approach:
    /// 1. Run both parties locally
    /// 2. Store device share locally, upload server share to KeyVault
    static func generateKey(
        serverURL: URL,
        curveCode: Int = 714
    ) async throws -> DKGResult {
        let client = ServerAPIClient(baseURL: serverURL)

        // Verify server is reachable and we're authenticated
        guard await client.isAuthenticated else {
            throw CBMPCError.authFailed
        }

        // Create DKG session on server (for audit trail)
        let dkgSession = try await client.createDKGSession(curveCode: curveCode)

        // Generate both shares locally
        let (publicKey, k0Data, k1Data) = try generateBothSharesLocally(curveCode: curveCode)

        // Upload Party 1 share to KeyVault
        let publicKeyHex = publicKey.map { String(format: "%02x", $0) }.joined()
        guard let deviceId = await client.currentDeviceId else {
            throw CBMPCError.authFailed
        }

        try await client.storeKeyShare(
            publicKey: publicKeyHex,
            curveCode: curveCode,
            serverShare: k1Data,
            participantDevices: [deviceId, "server"]
        )

        return DKGResult(
            publicKey: publicKey,
            deviceShare: k0Data,
            serverShare: k1Data,
            sessionId: dkgSession.session_id
        )
    }

    /// Generate both key shares locally and return them separately
    private static func generateBothSharesLocally(curveCode: Int) throws -> (publicKey: Data, share0: Data, share1: Data) {
        let partyNames = ["device", "server"]

        let (k0, k1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            var keyVar = cbmpc_ecdsa2p_key_t()
            let result = cbmpc_ecdsa2p_dkg(job.cJob, Int32(curveCode), &keyVar)
            guard result == 0 else { throw CBMPCError.keyGenerationFailed }
            return CBMPCKeyShare(keyPtr: keyVar, curveCode: curveCode)
        }

        guard let pubKey = k0.getPublicKey() else {
            throw CBMPCError.invalidKeyData
        }
        guard let ser0 = k0.serialize(), let ser1 = k1.serialize() else {
            throw CBMPCError.keySerializationFailed
        }

        return (pubKey, ser0, ser1)
    }
}
