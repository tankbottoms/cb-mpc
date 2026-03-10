import Foundation
import MultipeerConnectivity

/// Orchestrates peer-to-peer DKG via MultipeerConnectivity.
/// After a pairing ceremony completes, both devices can run DKG simultaneously —
/// Device A is Party 0, Device B is Party 1. Each device stores its own share.
class PeerDKGCoordinator {

    struct PeerDKGResult {
        let publicKey: Data
        let localShare: Data    // This device's share
        let curveCode: Int
    }

    /// Run DKG over an established MultipeerConnectivity session.
    /// - Parameters:
    ///   - session: The MCSession from the pairing flow
    ///   - remotePeerID: The connected peer
    ///   - localPartyId: 0 for initiator (Device A), 1 for joiner (Device B)
    ///   - curveCode: Elliptic curve code (default 714 = secp256k1)
    static func generateKey(
        session: MCSession,
        remotePeerID: MCPeerID,
        localPartyId: UInt16,
        curveCode: Int = 714
    ) throws -> PeerDKGResult {
        let transport = MultipeerTransport(
            session: session,
            localPartyId: localPartyId,
            remotePeerID: remotePeerID
        )

        let partyNames = ["device-a", "device-b"]
        let role: CBMPCPartyRole = localPartyId == 0 ? .party1 : .party2

        let cbmpcTransport = try CBMPCTransport(transport)
        let job = try CBMPCJob(role: role, partyNames: partyNames, transport: cbmpcTransport)

        var keyVar = cbmpc_ecdsa2p_key_t()
        let result = cbmpc_ecdsa2p_dkg(job.cJob, Int32(curveCode), &keyVar)
        guard result == 0 else {
            transport.abort()
            throw CBMPCError.keyGenerationFailed
        }

        let keyShare = CBMPCKeyShare(keyPtr: keyVar, curveCode: curveCode)

        guard let pubKey = keyShare.getPublicKey() else {
            transport.abort()
            throw CBMPCError.invalidKeyData
        }
        guard let serialized = keyShare.serialize() else {
            transport.abort()
            throw CBMPCError.keySerializationFailed
        }

        return PeerDKGResult(
            publicKey: pubKey,
            localShare: serialized,
            curveCode: curveCode
        )
    }
}
