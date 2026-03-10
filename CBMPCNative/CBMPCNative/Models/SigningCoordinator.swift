import Foundation

/// Unified signing coordinator for 2-party ECDSA signatures.
/// Routes to the appropriate signing mechanism based on ceremony type
/// (Device+Device via MultipeerConnectivity, Device+Server via REST API).
class SigningCoordinator {
    private let ceremonyCoordinator: CeremonyCoordinator

    init(ceremonyCoordinator: CeremonyCoordinator) {
        self.ceremonyCoordinator = ceremonyCoordinator
    }

    /// Sign a message using a Device+Server key.
    /// Wraps ServerSigningCoordinator.sign() with ceremony lifecycle tracking.
    @MainActor
    func signWithServer(
        message: Data,
        deviceShare: Data,
        curveCode: Int,
        serverURL: URL,
        publicKey: String
    ) async throws -> Data {
        let ceremony = try ceremonyCoordinator.createSigningCeremony(
            participantMode: .server,
            localPartyId: 0,
            messageHash: message
        )

        do {
            try ceremonyCoordinator.updateState(
                ceremonyId: ceremony.id,
                newState: .committed
            )

            let signature = try await ServerSigningCoordinator.sign(
                message: message,
                deviceShare: deviceShare,
                curveCode: curveCode,
                serverURL: serverURL,
                publicKey: publicKey
            )

            try ceremonyCoordinator.updateState(
                ceremonyId: ceremony.id,
                newState: .signed
            )

            try ceremonyCoordinator.completeCeremony(
                ceremonyId: ceremony.id,
                publicKey: publicKey,
                shareId: ""  // signing doesn't produce a new share
            )

            return signature
        } catch {
            try? ceremonyCoordinator.failCeremony(
                ceremonyId: ceremony.id,
                error: error.localizedDescription
            )
            throw error
        }
    }

    /// Sign a message using a Device+Device key.
    /// Placeholder -- requires peer connection for the actual 2-party signing protocol.
    @MainActor
    func signWithDevice(
        message: Data,
        keyId: UUID,
        peerConnectionManager: PeerConnectionManager
    ) async throws -> Data {
        let ceremony = try ceremonyCoordinator.createSigningCeremony(
            participantMode: .device,
            localPartyId: Int(peerConnectionManager.partyId),
            messageHash: message
        )

        do {
            try ceremonyCoordinator.updateState(
                ceremonyId: ceremony.id,
                newState: .committed
            )

            // TODO: Implement peer-to-peer signing protocol
            // 1. Retrieve local share from Keychain via KeyShareManager
            // 2. Exchange signing contributions with peer via PeerConnectionManager
            // 3. Combine partial signatures using CB-MPC FFI
            throw CeremonyCoordinator.CoordinatorError.invalidState(
                "Device+Device signing not yet implemented"
            )
        } catch {
            try? ceremonyCoordinator.failCeremony(
                ceremonyId: ceremony.id,
                error: error.localizedDescription
            )
            throw error
        }
    }
}
