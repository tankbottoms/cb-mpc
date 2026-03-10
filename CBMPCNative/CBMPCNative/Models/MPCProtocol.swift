import Foundation
import CryptoKit

/// Binary protocol encoder/decoder matching key-server's protocol.ts
/// Header format: [type:1][session_prefix:4][sender:2][receiver:2][payload_len:4][payload:N]
enum MPCProtocol {

    // MARK: - Message Types (matching key-server/src/types.ts)

    static let MSG_TYPE_DKG_MSG: UInt8        = 0x01
    static let MSG_TYPE_DKG_COMPLETE: UInt8    = 0x02
    static let MSG_TYPE_SIGN_REQUEST: UInt8    = 0x03
    static let MSG_TYPE_SIGN_MSG: UInt8        = 0x04
    static let MSG_TYPE_SIGN_COMPLETE: UInt8   = 0x05
    static let MSG_TYPE_ERROR: UInt8           = 0xFF

    /// Header size: type(1) + prefix(4) + sender(2) + receiver(2) + len(4) = 13
    static let headerSize = 13

    /// Broadcast receiver party ID
    static let broadcastReceiver: UInt16 = 0xFF

    // MARK: - Decoded Message

    struct Message {
        let type: UInt8
        let sessionPrefix: Data   // 4 bytes
        let senderPartyId: UInt16
        let receiverPartyId: UInt16
        let payload: Data
    }

    // MARK: - Encode

    static func encode(
        type: UInt8,
        sessionPrefix: Data,
        senderPartyId: UInt16,
        receiverPartyId: UInt16,
        payload: Data
    ) -> Data {
        var data = Data(capacity: headerSize + payload.count)

        // type (1 byte)
        data.append(type)

        // session prefix (4 bytes, pad/truncate)
        var prefix = Data(count: 4)
        let copyLen = min(sessionPrefix.count, 4)
        prefix.replaceSubrange(0..<copyLen, with: sessionPrefix.prefix(copyLen))
        data.append(prefix)

        // sender party ID (2 bytes, big-endian)
        var sender = senderPartyId.bigEndian
        data.append(Data(bytes: &sender, count: 2))

        // receiver party ID (2 bytes, big-endian)
        var receiver = receiverPartyId.bigEndian
        data.append(Data(bytes: &receiver, count: 2))

        // payload length (4 bytes, big-endian)
        var payloadLen = UInt32(payload.count).bigEndian
        data.append(Data(bytes: &payloadLen, count: 4))

        // payload
        data.append(payload)

        return data
    }

    // MARK: - Decode

    static func decode(_ data: Data) -> Message? {
        guard data.count >= headerSize else { return nil }

        let type = data[data.startIndex]

        let prefixStart = data.startIndex + 1
        let sessionPrefix = Data(data[prefixStart..<(prefixStart + 4)])

        let senderOffset = data.startIndex + 5
        let senderPartyId = UInt16(data[senderOffset]) << 8 | UInt16(data[senderOffset + 1])

        let receiverOffset = data.startIndex + 7
        let receiverPartyId = UInt16(data[receiverOffset]) << 8 | UInt16(data[receiverOffset + 1])

        let lenOffset = data.startIndex + 9
        let payloadLen = UInt32(data[lenOffset]) << 24
            | UInt32(data[lenOffset + 1]) << 16
            | UInt32(data[lenOffset + 2]) << 8
            | UInt32(data[lenOffset + 3])

        let payloadStart = data.startIndex + headerSize
        let payloadEnd = payloadStart + Int(payloadLen)
        guard payloadEnd <= data.endIndex else { return nil }

        let payload = Data(data[payloadStart..<payloadEnd])

        return Message(
            type: type,
            sessionPrefix: sessionPrefix,
            senderPartyId: senderPartyId,
            receiverPartyId: receiverPartyId,
            payload: payload
        )
    }

    // MARK: - Session Prefix

    /// Compute session prefix from session ID (SHA-256 first 4 bytes), matching server behavior
    static func sessionPrefix(from sessionId: String) -> Data {
        guard let idData = sessionId.data(using: .utf8) else { return Data(count: 4) }
        let digest = SHA256.hash(data: idData)
        return Data(digest.prefix(4))
    }

    // MARK: - DKG Complete Payload

    /// Encode DKG_COMPLETE payload: [pubkey_len:2][pubkey:N][share:M]
    static func encodeDKGComplete(publicKey: Data, share: Data) -> Data {
        var payload = Data()
        var pubLen = UInt16(publicKey.count).bigEndian
        payload.append(Data(bytes: &pubLen, count: 2))
        payload.append(publicKey)
        payload.append(share)
        return payload
    }

    /// Decode DKG_COMPLETE payload: [pubkey_len:2][pubkey:N][share:M]
    static func decodeDKGComplete(_ payload: Data) -> (publicKey: Data, share: Data)? {
        guard payload.count >= 2 else { return nil }
        let pubLen = UInt16(payload[payload.startIndex]) << 8 | UInt16(payload[payload.startIndex + 1])
        let pubStart = payload.startIndex + 2
        let pubEnd = pubStart + Int(pubLen)
        guard pubEnd <= payload.endIndex else { return nil }
        let publicKey = Data(payload[pubStart..<pubEnd])
        let share = Data(payload[pubEnd..<payload.endIndex])
        return (publicKey, share)
    }
}
