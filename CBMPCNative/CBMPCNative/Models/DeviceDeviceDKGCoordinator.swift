import Foundation
import MultipeerConnectivity

/// Orchestrates Device+Device DKG using CeremonyCoordinator for lifecycle management
/// and PeerDKGCoordinator for the actual cryptographic DKG operation.
class DeviceDeviceDKGCoordinator {
    private let ceremonyCoordinator: CeremonyCoordinator
    private let peerConnectionManager: PeerConnectionManager
    private let keyShareManager = KeyShareManager.shared
    private let timeoutInterval: TimeInterval = 30

    init(
        ceremonyCoordinator: CeremonyCoordinator,
        peerConnectionManager: PeerConnectionManager
    ) {
        self.ceremonyCoordinator = ceremonyCoordinator
        self.peerConnectionManager = peerConnectionManager
    }

    /// Run DKG as the local party. Uses PeerDKGCoordinator for the actual crypto,
    /// CeremonyCoordinator for state tracking, and KeyShareManager for storage.
    @MainActor
    func runDKG() async throws -> PeerDKGCoordinator.PeerDKGResult {
        let ceremony = try ceremonyCoordinator.createDKGCeremony(
            participantMode: .device,
            localPartyId: Int(peerConnectionManager.partyId)
        )

        do {
            // Update state to committed (DKG is starting)
            try ceremonyCoordinator.updateState(
                ceremonyId: ceremony.id,
                newState: .committed
            )

            // Run the actual DKG via PeerDKGCoordinator
            guard let remotePeer = peerConnectionManager.remotePeerID else {
                throw CeremonyCoordinator.CoordinatorError.invalidState("No connected peer")
            }

            let result = try PeerDKGCoordinator.generateKey(
                session: peerConnectionManager.mcSession,
                remotePeerID: remotePeer,
                localPartyId: peerConnectionManager.partyId,
                curveCode: 714
            )

            // Store the share in Keychain
            let keyId = ceremony.id
            let share = try await keyShareManager.storeShare(
                shareBytes: result.localShare,
                keyId: keyId,
                partyId: Int(peerConnectionManager.partyId),
                ceremonyType: "device_device",
                publicKey: result.publicKey.map { String(format: "%02x", $0) }.joined()
            )

            // Complete the ceremony
            try ceremonyCoordinator.completeCeremony(
                ceremonyId: ceremony.id,
                publicKey: share.publicKey,
                shareId: share.id
            )

            return result
        } catch {
            // Mark ceremony as failed
            try? ceremonyCoordinator.failCeremony(
                ceremonyId: ceremony.id,
                error: error.localizedDescription
            )
            throw error
        }
    }
}
