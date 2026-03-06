import Foundation

/// High-level crypto engine for key generation and signing
class CBMPCCryptoEngine {
    private let transport: CBMPCMockTransport

    init(transport: CBMPCMockTransport = CBMPCMockTransport()) {
        self.transport = transport
    }

    /// Generate an ECDSA 2-party key (simulated locally for demo)
    func generateKey(curveCode: Int) throws -> (publicKey: Data, serializedKey: Data) {
        do {
            print("[CryptoEngine] Starting key generation with curveCode: \(curveCode)")

            let wrappedTransport = try CBMPCTransport(transport)
            print("[CryptoEngine] Transport created successfully")

            let job = try CBMPCJob(role: .party1, partyNames: ["Local", "Remote"], transport: wrappedTransport)
            print("[CryptoEngine] Job created successfully")

            guard let cJob = job.cJob else {
                print("[CryptoEngine] ERROR: cJob is nil")
                throw CBMPCError.jobCreationFailed
            }

            var keyVar = cbmpc_ecdsa2p_key_t()
            print("[CryptoEngine] Calling cbmpc_ecdsa2p_dkg...")
            let result = cbmpc_ecdsa2p_dkg(cJob, Int32(curveCode), &keyVar)
            print("[CryptoEngine] DKG result: \(result)")

            guard result == 0 else {
                print("[CryptoEngine] ERROR: DKG failed with result: \(result)")
                throw CBMPCError.keyGenerationFailed
            }

            print("[CryptoEngine] Creating KeyShare...")
            let keyShare = CBMPCKeyShare(keyPtr: keyVar, curveCode: curveCode)

            // Extract public key
            guard let pubKey = keyShare.getPublicKey() else {
                print("[CryptoEngine] ERROR: Could not get public key")
                throw CBMPCError.invalidKeyData
            }

            // Serialize for storage
            guard let serialized = keyShare.serialize() else {
                print("[CryptoEngine] ERROR: Could not serialize key")
                throw CBMPCError.keySerializationFailed
            }

            print("[CryptoEngine] Key generation succeeded!")
            return (pubKey, serialized)
        } catch let error as CBMPCError {
            print("[CryptoEngine] CBMPCError: \(error)")
            throw error
        } catch {
            print("[CryptoEngine] Unexpected error: \(error)")
            throw CBMPCError.jobCreationFailed
        }
    }

    /// Sign a message with a deserialized key
    func signMessage(_ message: Data, keyData: Data, curveCode: Int) throws -> Data {
        do {
            // Deserialize the key
            let keyShare = try CBMPCKeyShare.deserialize(keyData, curveCode: curveCode)

            // Create a job for signing
            let wrappedTransport = try CBMPCTransport(transport)
            let job = try CBMPCJob(role: .party1, partyNames: ["Local", "Remote"], transport: wrappedTransport)

            // Generate a session ID
            let sessionId = UUID().uuidString.data(using: .utf8) ?? Data()

            // Sign the message
            let signatures = try CBMPCSigner.signMessages([message], with: keyShare, sessionId: sessionId, job: job)

            guard !signatures.isEmpty else {
                throw CBMPCError.signingFailed
            }

            // Return first signature (or combine if multiple)
            return signatures[0]
        } catch let error as CBMPCError {
            throw error
        } catch {
            throw CBMPCError.signingFailed
        }
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
}

/// Wrapper for storing serialized key data
struct SerializedKeyData {
    let publicKey: String // Hex-encoded compressed public key
    let serialized: Data // Full key share serialized
    let curveCode: Int32
}
