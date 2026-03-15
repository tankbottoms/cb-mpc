import Foundation

/// Wrapper around cbmpc_ecdsa2p_key_t for ECDSA 2-party key shares
class CBMPCKeyShare {
    var keyPtr: cbmpc_ecdsa2p_key_t
    let curveCode: Int

    /// Initialize from C key structure
    init(keyPtr: cbmpc_ecdsa2p_key_t, curveCode: Int) {
        self.keyPtr = keyPtr
        self.curveCode = curveCode
    }

    /// Get the party role for this key (0 or 1)
    func getRole() -> Int {
        Int(cbmpc_ecdsa2p_key_role(&keyPtr))
    }

    /// Extract the public key as compressed SEC1 format (33 bytes)
    func getPublicKey() -> Data? {
        let pubkey = cbmpc_ecdsa2p_key_pubkey(&keyPtr)
        guard pubkey.data != nil && pubkey.size > 0 else { return nil }
        defer { cbmpc_free(pubkey.data) }
        return Data(bytes: pubkey.data!, count: Int(pubkey.size))
    }

    /// Serialize the entire key share
    func serialize() -> Data? {
        let serialized = cbmpc_ecdsa2p_key_serialize(&keyPtr)
        guard serialized.data != nil && serialized.size > 0 else { return nil }
        defer { cbmpc_free(serialized.data) }
        return Data(bytes: serialized.data!, count: Int(serialized.size))
    }

    /// Deserialize a key share from bytes
    static func deserialize(_ data: Data, curveCode: Int) throws -> CBMPCKeyShare {
        var keyVar = cbmpc_ecdsa2p_key_t()
        let result = data.withUnsafeBytes { buffer in
            var cmem = cbmpc_cmem_t()
            cmem.data = UnsafeMutableRawPointer(mutating: buffer.baseAddress)
            cmem.size = Int32(data.count)
            return cbmpc_ecdsa2p_key_deserialize(cmem, &keyVar)
        }

        guard result == 0 else {
            throw CBMPCError.invalidKeyData
        }
        return CBMPCKeyShare(keyPtr: keyVar, curveCode: curveCode)
    }

    /// Get the curve code
    func getCurveCode() -> Int {
        Int(cbmpc_ecdsa2p_key_curve_code(&keyPtr))
    }

    /// Clean up memory
    deinit {
        cbmpc_ecdsa2p_key_free(keyPtr)
    }
}

/// Wrapper around cbmpc_hd_key_t for hierarchical deterministic keysets
class CBMPCHDKeyShare {
    var keyPtr: cbmpc_hd_key_t
    let curveCode: Int

    /// Initialize from C HD key structure
    init(keyPtr: cbmpc_hd_key_t, curveCode: Int) {
        self.keyPtr = keyPtr
        self.curveCode = curveCode
    }

    /// Extract the public key as compressed SEC1 format (33 bytes)
    func getPublicKey() -> Data? {
        let pubkey = cbmpc_hd_key_pubkey(&keyPtr)
        guard pubkey.data != nil && pubkey.size > 0 else { return nil }
        defer { cbmpc_free(pubkey.data) }
        return Data(bytes: pubkey.data!, count: Int(pubkey.size))
    }

    /// Serialize the HD key share
    func serialize() -> Data? {
        let serialized = cbmpc_hd_key_serialize(&keyPtr)
        guard serialized.data != nil && serialized.size > 0 else { return nil }
        defer { cbmpc_free(serialized.data) }
        return Data(bytes: serialized.data!, count: Int(serialized.size))
    }

    /// Deserialize an HD key share from bytes
    static func deserialize(_ data: Data, curveCode: Int) throws -> CBMPCHDKeyShare {
        var keyVar = cbmpc_hd_key_t()
        let result = data.withUnsafeBytes { buffer in
            var cmem = cbmpc_cmem_t()
            cmem.data = UnsafeMutableRawPointer(mutating: buffer.baseAddress)
            cmem.size = Int32(data.count)
            return cbmpc_hd_key_deserialize(cmem, &keyVar)
        }

        guard result == 0 else {
            throw CBMPCError.invalidKeyData
        }
        return CBMPCHDKeyShare(keyPtr: keyVar, curveCode: curveCode)
    }

    /// Derive a child key at the given BIP32 path
    func derive(path: [UInt32], job: CBMPCJob) throws -> CBMPCKeyShare {
        guard let cJob = job.cJob else {
            throw CBMPCError.jobCreationFailed
        }

        var childKeyVar = cbmpc_ecdsa2p_key_t()
        var pathArray = path.map(Int32.init)

        let result = cbmpc_hd_ecdsa2p_derive(
            cJob,
            &keyPtr,
            &pathArray,
            Int32(pathArray.count),
            &childKeyVar
        )

        guard result == 0 else {
            throw CBMPCError.keyGenerationFailed
        }
        return CBMPCKeyShare(keyPtr: childKeyVar, curveCode: curveCode)
    }

    /// Clean up memory
    deinit {
        cbmpc_hd_key_free(keyPtr)
    }
}
