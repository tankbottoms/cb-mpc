import Foundation
import MultipeerConnectivity

/// Orchestrates peer-to-peer signing via MultipeerConnectivity.
/// Parallel to PeerDKGCoordinator but for signing operations.
/// Both devices must have their key share available locally.
class PeerSigningCoordinator {

    struct PeerSignResult {
        let signature: Data      // DER-encoded signature
        let messageHash: Data    // The hash that was signed
    }

    /// Sign a message over an established MultipeerConnectivity session.
    /// - Parameters:
    ///   - session: The MCSession from the pairing/reconnection flow
    ///   - remotePeerID: The connected peer
    ///   - localPartyId: 0 for initiator (Device A), 1 for joiner (Device B)
    ///   - keyShare: The local party's deserialized key share
    ///   - messageHash: 32-byte SHA-256 hash of the message to sign
    ///   - curveCode: Elliptic curve code (default 714 = secp256k1)
    static func sign(
        session: MCSession,
        remotePeerID: MCPeerID,
        localPartyId: UInt16,
        keyShare: CBMPCKeyShare,
        messageHash: Data,
        curveCode: Int = 714
    ) throws -> PeerSignResult {
        let transport = MultipeerTransport(
            session: session,
            localPartyId: localPartyId,
            remotePeerID: remotePeerID
        )

        let partyNames = ["device-a", "device-b"]
        let role: CBMPCPartyRole = localPartyId == 0 ? .party1 : .party2
        let sessionId = UUID().uuidString.data(using: .utf8) ?? Data()

        let cbmpcTransport = try CBMPCTransport(transport)
        let job = try CBMPCJob(role: role, partyNames: partyNames, transport: cbmpcTransport)

        let signatures = try CBMPCSigner.signMessages(
            [messageHash],
            with: keyShare,
            sessionId: sessionId,
            job: job
        )

        // In 2-party ECDSA, only party 0 receives the final signature
        if localPartyId == 0 {
            guard let sig = signatures.first, !sig.isEmpty else {
                transport.abort()
                throw CBMPCError.signingFailed
            }
            return PeerSignResult(signature: sig, messageHash: messageHash)
        } else {
            // Party 1 participates but doesn't receive the signature output
            // The caller (SigningCoordinator) handles collecting from party 0
            return PeerSignResult(signature: Data(), messageHash: messageHash)
        }
    }
}
