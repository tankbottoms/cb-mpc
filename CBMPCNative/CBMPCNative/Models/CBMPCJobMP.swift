import Foundation

/// Wrapper around cbmpc_jobmp_t for N-party MPC operations
class CBMPCJobMP {
    private var jobPtr: UnsafeMutablePointer<cbmpc_jobmp_t>?
    private let transport: CBMPCTransport

    /// Initialize with party role, count, and names
    init(partyCount: Int, role: Int, partyNames: [String], transport: CBMPCTransport) throws {
        self.transport = transport

        var cNames: [UnsafePointer<CChar>?] = []
        var allocated: [UnsafeMutablePointer<CChar>] = []

        for name in partyNames {
            let cStr = UnsafeMutablePointer<CChar>.allocate(capacity: name.count + 1)
            _ = name.withCString { strcpy(cStr, $0) }
            allocated.append(cStr)
            cNames.append(UnsafePointer(cStr))
        }

        let ptr = cNames.withUnsafeBytes { buffer in
            let base = buffer.baseAddress?.assumingMemoryBound(to: (UnsafePointer<CChar>?).self)
            return cbmpc_jobmp_new(transport.callbacksPtr, transport.contextPtr,
                                   Int32(partyCount), Int32(role), base, Int32(partyNames.count))
        }

        for p in allocated { p.deallocate() }

        guard let valid = ptr else {
            throw CBMPCError.jobCreationFailed
        }
        self.jobPtr = valid
    }

    var cJob: UnsafeMutablePointer<cbmpc_jobmp_t>? { jobPtr }

    func getPartyIndex() -> Int {
        guard let ptr = jobPtr else { return -1 }
        return Int(cbmpc_jobmp_role(ptr))
    }

    func getPartyCount() -> Int {
        guard let ptr = jobPtr else { return -1 }
        return Int(cbmpc_jobmp_n_parties(ptr))
    }

    deinit {
        if let ptr = jobPtr {
            cbmpc_jobmp_free(ptr)
        }
    }
}
