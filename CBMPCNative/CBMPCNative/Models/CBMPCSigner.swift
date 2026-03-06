import Foundation

/// Wrapper for ECDSA 2-party signing operations
class CBMPCSigner {
    /// Sign messages using a key share
    static func signMessages(
        _ messages: [Data],
        with key: CBMPCKeyShare,
        sessionId: Data,
        job: CBMPCJob
    ) throws -> [Data] {
        guard let cJob = job.cJob else {
            throw CBMPCError.jobCreationFailed
        }

        // Create flattened message buffer
        let totalSize = messages.reduce(0) { $0 + $1.count }
        let flatMsgBuffer = malloc(totalSize)!.assumingMemoryBound(to: UInt8.self)
        var sizeArray = [Int32]()
        var offset = 0

        for msg in messages {
            _ = msg.copyBytes(to: UnsafeMutableBufferPointer(start: flatMsgBuffer + offset, count: msg.count))
            sizeArray.append(Int32(msg.count))
            offset += msg.count
        }

        // Prepare message struct
        var msgs = cbmpc_cmems_t()
        msgs.count = Int32(messages.count)
        msgs.data = UnsafeMutableRawPointer(flatMsgBuffer)
        msgs.sizes = malloc(sizeArray.count * MemoryLayout<Int32>.size)!.assumingMemoryBound(to: Int32.self)
        _ = sizeArray.withUnsafeBufferPointer { sizeBuffer in
            sizeBuffer.baseAddress.flatMap { src in
                memcpy(msgs.sizes, src, sizeArray.count * MemoryLayout<Int32>.size)
            }
        }

        defer {
            free(flatMsgBuffer)
            free(msgs.sizes)
        }

        // Prepare signatures output
        var sigs = cbmpc_cmems_t()

        // Prepare session ID
        var sidMem = cbmpc_cmem_t()
        let sidBuffer = malloc(sessionId.count)!.assumingMemoryBound(to: UInt8.self)
        _ = sessionId.copyBytes(to: UnsafeMutableBufferPointer(start: sidBuffer, count: sessionId.count))
        sidMem.data = UnsafeMutableRawPointer(sidBuffer)
        sidMem.size = Int32(sessionId.count)

        defer { free(sidBuffer) }

        // Call signing function
        let result = withUnsafeMutableBytes(of: &key.keyPtr) { keyBuffer in
            var mutableKey = keyBuffer.load(as: cbmpc_ecdsa2p_key_t.self)
            return cbmpc_ecdsa2p_sign(
                cJob,
                sidMem,
                &mutableKey,
                msgs,
                &sigs
            )
        }

        guard result == 0 else {
            throw CBMPCError.signingFailed
        }

        // Extract signatures -- in 2-party ECDSA, only one party receives
        // the signature output; the other party gets sigs.data == nil
        var signatures: [Data] = []

        guard let flatSigPtr = sigs.data, let sigSizes = sigs.sizes else {
            // This party didn't receive signatures (normal for party 2)
            return signatures
        }

        let flatSigBuffer = flatSigPtr.assumingMemoryBound(to: UInt8.self)
        var sigOffset = 0

        for i in 0..<Int(sigs.count) {
            let size = (sigSizes + i).pointee
            let sigData = Data(bytes: flatSigBuffer + sigOffset, count: Int(size))
            signatures.append(sigData)
            sigOffset += Int(size)
        }

        defer {
            cbmpc_free(sigs.data)
            cbmpc_free(sigs.sizes)
        }

        return signatures
    }
}
