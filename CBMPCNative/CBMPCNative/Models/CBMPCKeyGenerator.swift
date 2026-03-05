import Foundation

/// Wrapper for ECDSA 2-party key generation (DKG)
class CBMPCKeyGenerator {
    /// Perform distributed key generation for ECDSA 2-party
    static func generateECDSAKey(
        curveCode: Int,
        job: CBMPCJob
    ) throws -> CBMPCKeyShare {
        guard let cJob = job.cJob else {
            throw CBMPCError.jobCreationFailed
        }

        var keyVar = cbmpc_ecdsa2p_key_t()
        let result = cbmpc_ecdsa2p_dkg(cJob, Int32(curveCode), &keyVar)

        guard result == 0 else {
            throw CBMPCError.keyGenerationFailed
        }
        return CBMPCKeyShare(keyPtr: keyVar, curveCode: curveCode)
    }

    /// Perform key refresh on an existing key
    static func refreshKey(
        _ key: CBMPCKeyShare,
        job: CBMPCJob
    ) throws -> CBMPCKeyShare {
        guard let cJob = job.cJob else {
            throw CBMPCError.jobCreationFailed
        }

        var newKeyVar = cbmpc_ecdsa2p_key_t()
        let result = withUnsafeMutableBytes(of: &key.keyPtr) { keyBuffer in
            var mutableKey = keyBuffer.load(as: cbmpc_ecdsa2p_key_t.self)
            return cbmpc_ecdsa2p_refresh(cJob, &mutableKey, &newKeyVar)
        }

        guard result == 0 else {
            throw CBMPCError.keyGenerationFailed
        }
        return CBMPCKeyShare(keyPtr: newKeyVar, curveCode: key.curveCode)
    }

    /// Perform distributed key generation for HD keyset
    static func generateHDKey(
        curveCode: Int,
        job: CBMPCJob
    ) throws -> CBMPCHDKeyShare {
        guard let cJob = job.cJob else {
            throw CBMPCError.jobCreationFailed
        }

        var keyVar = cbmpc_hd_key_t()
        let result = cbmpc_hd_ecdsa2p_dkg(cJob, Int32(curveCode), &keyVar)

        guard result == 0 else {
            throw CBMPCError.keyGenerationFailed
        }
        return CBMPCHDKeyShare(keyPtr: keyVar, curveCode: curveCode)
    }

    /// Refresh an HD keyset
    static func refreshHDKey(
        _ key: CBMPCHDKeyShare,
        job: CBMPCJob
    ) throws -> CBMPCHDKeyShare {
        guard let cJob = job.cJob else {
            throw CBMPCError.jobCreationFailed
        }

        var newKeyVar = cbmpc_hd_key_t()
        let result = withUnsafeMutableBytes(of: &key.keyPtr) { keyBuffer in
            var mutableKey = keyBuffer.load(as: cbmpc_hd_key_t.self)
            return cbmpc_hd_ecdsa2p_refresh(cJob, &mutableKey, &newKeyVar)
        }

        guard result == 0 else {
            throw CBMPCError.keyGenerationFailed
        }
        return CBMPCHDKeyShare(keyPtr: newKeyVar, curveCode: key.curveCode)
    }
}
