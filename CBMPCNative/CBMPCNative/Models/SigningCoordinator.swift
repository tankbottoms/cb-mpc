import Foundation
import CryptoKit

/// Unified signing coordinator for 2-party ECDSA signatures.
/// Routes to the appropriate signing mechanism based on ceremony type
/// (Device+Device via MultipeerConnectivity, Device+Server via REST API).
class SigningCoordinator {
    private let ceremonyCoordinator: CeremonyCoordinator
    private let keyShareManager = KeyShareManager.shared

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
    /// Uses PeerSigningCoordinator to execute the 2-party signing protocol
    /// over MultipeerConnectivity.
    @MainActor
    func signWithDevice(
        message: Data,
        keyId: UUID,
        peerConnectionManager: PeerConnectionManager,
        curveCode: Int = 714
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

            // Retrieve local share from Keychain
            let partyId = Int(peerConnectionManager.partyId)
            let shareId = "cb-mpc.share.\(keyId.uuidString).\(partyId)"
            let shareData = try await keyShareManager.retrieveShare(shareId: shareId)
            let keyShare = try CBMPCKeyShare.deserialize(shareData, curveCode: curveCode)

            // Pre-hash the message if not already 32 bytes
            let messageHash: Data
            if message.count == 32 {
                messageHash = message
            } else {
                messageHash = Data(SHA256.hash(data: message))
            }

            // Execute peer-to-peer signing via MultipeerConnectivity
            guard let remotePeer = peerConnectionManager.remotePeerID else {
                throw CeremonyCoordinator.CoordinatorError.invalidState("No connected peer")
            }

            let result = try PeerSigningCoordinator.sign(
                session: peerConnectionManager.mcSession,
                remotePeerID: remotePeer,
                localPartyId: peerConnectionManager.partyId,
                keyShare: keyShare,
                messageHash: messageHash,
                curveCode: curveCode
            )

            try ceremonyCoordinator.updateState(
                ceremonyId: ceremony.id,
                newState: .signed
            )

            let publicKeyHex = keyShare.getPublicKey()?.map { String(format: "%02x", $0) }.joined() ?? ""
            try ceremonyCoordinator.completeCeremony(
                ceremonyId: ceremony.id,
                publicKey: publicKeyHex,
                shareId: ""
            )

            return result.signature
        } catch {
            try? ceremonyCoordinator.failCeremony(
                ceremonyId: ceremony.id,
                error: error.localizedDescription
            )
            throw error
        }
    }
}
