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
        print("[ServerDKG] Checking server auth at \(serverURL.absoluteString)...")
        guard await client.isAuthenticated else {
            print("[ServerDKG] ERROR: Not authenticated with server")
            throw CBMPCError.authFailed
        }
        print("[ServerDKG] Authenticated. Creating DKG session...")

        // Create DKG session on server (for audit trail)
        let dkgSession = try await client.createDKGSession(curveCode: curveCode)
        print("[ServerDKG] DKG session created: \(dkgSession.session_id), status=\(dkgSession.status)")

        // Generate both shares locally
        print("[ServerDKG] Generating 2-party key shares locally (curve=\(curveCode))...")
        let (publicKey, k0Data, k1Data) = try generateBothSharesLocally(curveCode: curveCode)
        let publicKeyHex = publicKey.map { String(format: "%02x", $0) }.joined()
        print("[ServerDKG] Shares generated — Party0=\(k0Data.count) bytes, Party1=\(k1Data.count) bytes, pubKey=\(String(publicKeyHex.prefix(16)))...")

        // Upload Party 1 share to KeyVault
        guard let deviceId = await client.currentDeviceId else {
            print("[ServerDKG] ERROR: No device ID available")
            throw CBMPCError.authFailed
        }

        print("[ServerDKG] Uploading Party1 share to KeyVault (deviceId=\(deviceId))...")
        try await client.storeKeyShare(
            publicKey: publicKeyHex,
            curveCode: curveCode,
            serverShare: k1Data,
            participantDevices: [deviceId, "server"]
        )
        print("[ServerDKG] Party1 share uploaded to server successfully")

        return DKGResult(
            publicKey: publicKey,
            deviceShare: k0Data,
            serverShare: k1Data,
            sessionId: dkgSession.session_id
        )
    }

    /// Generate a server-backed key with ceremony lifecycle tracking.
    /// Wraps the existing generateKey flow with CeremonyCoordinator state management
    /// and stores the device share in Keychain via KeyShareManager.
    @MainActor
    static func generateKeyWithCeremony(
        serverURL: URL,
        ceremonyCoordinator: CeremonyCoordinator,
        curveCode: Int = 714
    ) async throws -> DKGResult {
        let ceremony = try ceremonyCoordinator.createDKGCeremony(
            participantMode: .server,
            localPartyId: 0
        )

        do {
            try ceremonyCoordinator.updateState(
                ceremonyId: ceremony.id,
                newState: .committed
            )

            // Run existing DKG flow
            let result = try await generateKey(
                serverURL: serverURL,
                curveCode: curveCode
            )

            // Store device share in Keychain
            let keyShareManager = KeyShareManager.shared
            let publicKeyHex = result.publicKey.map { String(format: "%02x", $0) }.joined()
            let share = try await keyShareManager.storeShare(
                shareBytes: result.deviceShare,
                keyId: ceremony.id,
                partyId: 0,
                ceremonyType: "device_server",
                publicKey: publicKeyHex
            )

            try ceremonyCoordinator.completeCeremony(
                ceremonyId: ceremony.id,
                publicKey: publicKeyHex,
                shareId: share.id
            )

            return result
        } catch {
            try? ceremonyCoordinator.failCeremony(
                ceremonyId: ceremony.id,
                error: error.localizedDescription
            )
            throw error
        }
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
