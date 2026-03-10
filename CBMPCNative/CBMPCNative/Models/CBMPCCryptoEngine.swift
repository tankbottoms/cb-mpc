import Foundation

/// High-level crypto engine for key generation and signing
class CBMPCCryptoEngine {

    /// Generate an ECDSA 2-party key using LocalTwoPartyRunner
    /// Stores both party shares in a length-prefixed format: [UInt32 k0Size][k0 bytes][k1 bytes]
    func generateKey(curveCode: Int) throws -> (publicKey: Data, serializedKey: Data) {
        let partyNames = ["local", "remote"]

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

        // Pack both shares: [4 bytes k0 length][k0 bytes][k1 bytes]
        var combined = Data()
        var k0Size = UInt32(ser0.count)
        combined.append(Data(bytes: &k0Size, count: 4))
        combined.append(ser0)
        combined.append(ser1)

        return (pubKey, combined)
    }

    /// Sign a message with both deserialized key shares using LocalTwoPartyRunner
    func signMessage(_ message: Data, keyData: Data, curveCode: Int) throws -> Data {
        let (keyShare0, keyShare1) = try Self.unpackKeyShares(keyData, curveCode: curveCode)

        let sessionId = UUID().uuidString.data(using: .utf8) ?? Data()
        let partyNames = ["local", "remote"]

        let (sig0, _) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let keyShare = (role == 0) ? keyShare0 : keyShare1
            let sigs = try CBMPCSigner.signMessages([message], with: keyShare, sessionId: sessionId, job: job)
            return sigs.first ?? Data()
        }

        guard !sig0.isEmpty else { throw CBMPCError.signingFailed }
        return sig0
    }

    /// Unpack length-prefixed key share data into two separate shares
    static func unpackKeyShares(_ data: Data, curveCode: Int) throws -> (CBMPCKeyShare, CBMPCKeyShare) {
        guard data.count > 4 else { throw CBMPCError.invalidKeyData }

        let k0Size = data.withUnsafeBytes { buf in
            buf.load(as: UInt32.self)
        }
        let k0Start = 4
        let k0End = k0Start + Int(k0Size)
        guard k0End <= data.count else { throw CBMPCError.invalidKeyData }

        let ser0 = data[k0Start..<k0End]
        let ser1 = data[k0End...]

        guard !ser0.isEmpty, !ser1.isEmpty else { throw CBMPCError.invalidKeyData }

        let share0 = try CBMPCKeyShare.deserialize(Data(ser0), curveCode: curveCode)
        let share1 = try CBMPCKeyShare.deserialize(Data(ser1), curveCode: curveCode)
        return (share0, share1)
    }

    /// Verify an ECDSA signature (stateless, no key share needed)
    static func verifySignature(curveCode: Int, publicKey: Data, messageHash: Data, derSignature: Data) -> Bool {
        let result = publicKey.withUnsafeBytes { pubBuf in
            messageHash.withUnsafeBytes { hashBuf in
                derSignature.withUnsafeBytes { sigBuf in
                    var pubMem = cbmpc_cmem_t()
                    pubMem.data = UnsafeMutableRawPointer(mutating: pubBuf.baseAddress)
                    pubMem.size = Int32(publicKey.count)

                    var hashMem = cbmpc_cmem_t()
                    hashMem.data = UnsafeMutableRawPointer(mutating: hashBuf.baseAddress)
                    hashMem.size = Int32(messageHash.count)

                    var sigMem = cbmpc_cmem_t()
                    sigMem.data = UnsafeMutableRawPointer(mutating: sigBuf.baseAddress)
                    sigMem.size = Int32(derSignature.count)

                    return cbmpc_ecdsa_verify(Int32(curveCode), pubMem, hashMem, sigMem)
                }
            }
        }
        return result == 0
    }

    /// Format a signature as hex string for display
    static func formatSignature(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Parse hex string back to Data
    static func parseSignatureHex(_ hex: String) -> Data? {
        let cleanHex = hex.filter { !$0.isWhitespace }
        guard cleanHex.count % 2 == 0 else { return nil }

        var data = Data()
        for i in stride(from: 0, to: cleanHex.count, by: 2) {
            let start = cleanHex.index(cleanHex.startIndex, offsetBy: i)
            let end = cleanHex.index(start, offsetBy: 2)
            if let byte = UInt8(cleanHex[start..<end], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
        }
        return data
    }

    // MARK: - Server-Backed Operations

    /// Generate key with server — device keeps Party 0 share only
    func generateKeyRemote(serverURL: URL, curveCode: Int = 714) async throws -> (publicKey: Data, deviceShare: Data) {
        let result = try await ServerDKGCoordinator.generateKey(serverURL: serverURL, curveCode: curveCode)
        return (result.publicKey, result.deviceShare)
    }

    /// Sign with server-backed key — interim approach: run both parties locally
    /// using device share + reconstructed full key data
    /// In the future, this will use WebSocket transport to sign with the server
    func signMessageRemote(_ message: Data, deviceShare: Data, curveCode: Int, serverURL: URL, publicKey: String) async throws -> Data {
        // Interim: use ServerSigningCoordinator which runs both shares locally
        return try await ServerSigningCoordinator.sign(
            message: message,
            deviceShare: deviceShare,
            curveCode: curveCode,
            serverURL: serverURL,
            publicKey: publicKey
        )
    }
}

/// Wrapper for storing serialized key data
struct SerializedKeyData {
    let publicKey: String // Hex-encoded compressed public key
    let serialized: Data // Full key share serialized
    let curveCode: Int32
}
