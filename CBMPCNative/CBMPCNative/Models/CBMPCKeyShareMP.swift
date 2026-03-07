import Foundation

/// Wrapper around cbmpc_eckey_mp_t for multi-party EC key shares
class CBMPCKeyShareMP {
    var keyPtr: cbmpc_eckey_mp_t

    init(keyPtr: cbmpc_eckey_mp_t) {
        self.keyPtr = keyPtr
    }

    deinit {
        cbmpc_eckey_mp_free(keyPtr)
    }

    /// Get the compressed SEC1 public key
    func getPublicKey() -> Data? {
        let mem = cbmpc_eckey_mp_pubkey(&keyPtr)
        guard let data = mem.data else { return nil }
        let result = Data(bytes: data, count: Int(mem.size))
        cbmpc_free(data)
        return result
    }

    /// Get the party name for this key share
    func getPartyName() -> String? {
        let mem = cbmpc_eckey_mp_party_name(&keyPtr)
        guard let data = mem.data else { return nil }
        let result = String(bytes: Data(bytes: data, count: Int(mem.size)), encoding: .utf8)
        cbmpc_free(data)
        return result
    }

    /// Get the private x_share as bytes
    func getXShare() -> Data? {
        let mem = cbmpc_eckey_mp_x_share(&keyPtr)
        guard let data = mem.data else { return nil }
        let result = Data(bytes: data, count: Int(mem.size))
        cbmpc_free(data)
        return result
    }

    /// Serialize to bytes for storage
    func serialize() -> cbmpc_cmems_t? {
        var out = cbmpc_cmems_t()
        let result = cbmpc_eckey_mp_serialize(&keyPtr, &out)
        guard result == 0 else { return nil }
        return out
    }

    /// Deserialize from bytes
    static func deserialize(_ data: cbmpc_cmems_t) throws -> CBMPCKeyShareMP {
        var mutableData = data
        var keyVar = cbmpc_eckey_mp_t()
        let result = cbmpc_eckey_mp_deserialize(mutableData, &keyVar)
        guard result == 0 else { throw CBMPCError.invalidKeyData }
        return CBMPCKeyShareMP(keyPtr: keyVar)
    }
}
