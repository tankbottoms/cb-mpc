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

    // MARK: - HD Key Generation (BIP-32 Hierarchical Deterministic)

    /// Generate a server-backed HD master key using the interim approach:
    /// 1. Run both parties locally with cbmpc_hd_ecdsa2p_dkg
    /// 2. Store device HD share locally, upload server HD share to KeyVault
    static func generateHDKey(
        serverURL: URL,
        curveCode: Int = 714
    ) async throws -> DKGResult {
        let client = ServerAPIClient(baseURL: serverURL)

        print("[ServerDKG-HD] Checking server auth at \(serverURL.absoluteString)...")
        guard await client.isAuthenticated else {
            print("[ServerDKG-HD] ERROR: Not authenticated with server")
            throw CBMPCError.authFailed
        }
        print("[ServerDKG-HD] Authenticated. Creating HD DKG session...")

        let dkgSession = try await client.createDKGSession(curveCode: curveCode)
        print("[ServerDKG-HD] DKG session created: \(dkgSession.session_id)")

        print("[ServerDKG-HD] Generating 2-party HD key shares locally (curve=\(curveCode))...")
        let (publicKey, k0Data, k1Data) = try generateBothHDSharesLocally(curveCode: curveCode)
        let publicKeyHex = publicKey.map { String(format: "%02x", $0) }.joined()
        print("[ServerDKG-HD] HD shares generated — Party0=\(k0Data.count) bytes, Party1=\(k1Data.count) bytes, pubKey=\(String(publicKeyHex.prefix(16)))...")

        guard let deviceId = await client.currentDeviceId else {
            print("[ServerDKG-HD] ERROR: No device ID available")
            throw CBMPCError.authFailed
        }

        print("[ServerDKG-HD] Uploading Party1 HD share to KeyVault...")
        try await client.storeKeyShare(
            publicKey: publicKeyHex,
            curveCode: curveCode,
            serverShare: k1Data,
            participantDevices: [deviceId, "server"]
        )
        print("[ServerDKG-HD] Party1 HD share uploaded successfully")

        return DKGResult(
            publicKey: publicKey,
            deviceShare: k0Data,
            serverShare: k1Data,
            sessionId: dkgSession.session_id
        )
    }

    /// Derive a child key from a server-backed HD master.
    /// Downloads server's HD master share, runs derivation locally with both shares,
    /// uploads child Party 1 share to server, returns child Party 0 share.
    static func deriveChild(
        deviceHDShare: Data,
        path: [UInt32],
        curveCode: Int,
        serverURL: URL,
        masterPublicKey: String
    ) async throws -> (publicKey: Data, deviceChildShare: Data, serverChildShare: Data) {
        let client = ServerAPIClient(baseURL: serverURL)

        guard await client.isAuthenticated else {
            throw CBMPCError.authFailed
        }

        // Download server's HD master share
        print("[ServerDKG-HD] Downloading server HD master share for derivation...")
        let keyInfo = try await client.getKey(publicKey: masterPublicKey)
        guard let serverShareB64 = keyInfo.server_share,
              let serverHDShare = Data(base64Encoded: serverShareB64) else {
            throw CBMPCError.transportError("Server did not return HD master share")
        }

        // Deserialize both HD shares
        let hdShare0 = try CBMPCHDKeyShare.deserialize(deviceHDShare, curveCode: curveCode)
        let hdShare1 = try CBMPCHDKeyShare.deserialize(serverHDShare, curveCode: curveCode)

        let partyNames = ["device", "server"]

        // Run HD derivation with both parties
        print("[ServerDKG-HD] Deriving child key at path \(path)...")
        let (child0, child1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let hdShare = (role == 0) ? hdShare0 : hdShare1
            return try hdShare.derive(path: path, job: job)
        }

        guard let childPubKey = child0.getPublicKey() else {
            throw CBMPCError.invalidKeyData
        }
        guard let childSer0 = child0.serialize(), let childSer1 = child1.serialize() else {
            throw CBMPCError.keySerializationFailed
        }

        // Upload child Party 1 share to server
        let childPubKeyHex = childPubKey.map { String(format: "%02x", $0) }.joined()
        guard let deviceId = await client.currentDeviceId else {
            throw CBMPCError.authFailed
        }

        print("[ServerDKG-HD] Uploading child Party1 share to KeyVault...")
        try await client.storeKeyShare(
            publicKey: childPubKeyHex,
            curveCode: curveCode,
            serverShare: childSer1,
            participantDevices: [deviceId, "server"]
        )
        print("[ServerDKG-HD] Child key derived and stored — pubKey=\(String(childPubKeyHex.prefix(16)))...")

        return (childPubKey, childSer0, childSer1)
    }

    // MARK: - Private

    /// Generate both standard key shares locally and return them separately
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

    /// Generate both HD key shares locally and return them separately
    private static func generateBothHDSharesLocally(curveCode: Int) throws -> (publicKey: Data, share0: Data, share1: Data) {
        let partyNames = ["device", "server"]

        let (k0, k1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            var keyVar = cbmpc_hd_key_t()
            let result = cbmpc_hd_ecdsa2p_dkg(job.cJob, Int32(curveCode), &keyVar)
            guard result == 0 else { throw CBMPCError.keyGenerationFailed }
            return CBMPCHDKeyShare(keyPtr: keyVar, curveCode: curveCode)
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
