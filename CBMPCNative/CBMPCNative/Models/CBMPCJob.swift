import Foundation

/// Wrapper around cbmpc_job2p_t for 2-party MPC operations
class CBMPCJob {
    private var jobPtr: UnsafeMutablePointer<cbmpc_job2p_t>?
    private let transport: CBMPCTransport

    /// Initialize with party role and names
    init(role: CBMPCPartyRole, partyNames: [String], transport: CBMPCTransport) throws {
        self.transport = transport

        // Create C-compatible party names (allocate and copy)
        var cNames: [UnsafePointer<CChar>?] = []
        var allocatedPointers: [UnsafeMutablePointer<CChar>] = []

        for name in partyNames {
            let cStr = UnsafeMutablePointer<CChar>.allocate(capacity: name.count + 1)
            _ = name.withCString { str in
                strcpy(cStr, str)
            }
            allocatedPointers.append(cStr)
            cNames.append(UnsafePointer(cStr))
        }

        // Create job - convert array to const char* const*
        let jobPtr = cNames.withUnsafeBytes { buffer in
            let basePtr = buffer.baseAddress?.assumingMemoryBound(to: (UnsafePointer<CChar>?).self)
            return cbmpc_job2p_new(transport.callbacksPtr, transport.contextPtr, Int32(role.rawValue), basePtr, Int32(partyNames.count))
        }

        // Cleanup C strings
        for cName in allocatedPointers {
            cName.deallocate()
        }

        guard let validJobPtr = jobPtr else {
            throw CBMPCError.jobCreationFailed
        }
        self.jobPtr = validJobPtr
    }

    func getPartyIndex() -> Int {
        guard let ptr = jobPtr else { return -1 }
        return Int(cbmpc_job2p_role(ptr))
    }

    deinit {
        if let ptr = jobPtr {
            cbmpc_job2p_free(ptr)
        }
    }

    var cJob: UnsafeMutablePointer<cbmpc_job2p_t>? {
        jobPtr
    }
}

/// Party role for 2-party MPC
enum CBMPCPartyRole: Int {
    case party1 = 0
    case party2 = 1
}

/// Network transport interface
protocol CBMPCTransportInterface {
    func send(receiver: Int, message: Data) -> Int
    func receive(sender: Int) -> Result<Data, CBMPCError>
    func receiveAll(senders: [Int]) -> Result<[Data], CBMPCError>
}

/// Transport wrapper
class CBMPCTransport {
    let callbacksPtr: UnsafeMutablePointer<cbmpc_transport_t>
    var contextPtr: UnsafeMutableRawPointer
    private let transportImpl: CBMPCTransportInterface

    init(_ transport: CBMPCTransportInterface) throws {
        self.transportImpl = transport
        self.callbacksPtr = UnsafeMutablePointer<cbmpc_transport_t>.allocate(capacity: 1)
        self.contextPtr = UnsafeMutableRawPointer(bitPattern: 1)! // Temporary non-nil placeholder, replaced after init

        callbacksPtr.pointee.send_fn = { (ctx, receiver, msg) -> Int32 in
            guard let ctx = ctx else { return -1 }
            let transport = Unmanaged<CBMPCTransport>.fromOpaque(ctx).takeUnretainedValue()
            let data = Data(bytes: msg.data!, count: Int(msg.size))
            return Int32(transport.transportImpl.send(receiver: Int(receiver), message: data))
        }

        callbacksPtr.pointee.receive_fn = { (ctx, sender, msg) -> Int32 in
            guard let ctx = ctx, let msg = msg else { return -1 }
            let transport = Unmanaged<CBMPCTransport>.fromOpaque(ctx).takeUnretainedValue()
            switch transport.transportImpl.receive(sender: Int(sender)) {
            case .success(let data):
                msg.pointee.data = malloc(data.count)
                if let buffer = msg.pointee.data?.assumingMemoryBound(to: UInt8.self) {
                    _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: buffer, count: data.count))
                }
                msg.pointee.size = Int32(data.count)
                return 0
            case .failure:
                return -1
            }
        }

        callbacksPtr.pointee.receive_all_fn = { (ctx, senders, count, msgs) -> Int32 in
            guard let ctx = ctx, let msgs = msgs else { return -1 }
            let transport = Unmanaged<CBMPCTransport>.fromOpaque(ctx).takeUnretainedValue()
            let senderArray = Array(UnsafeBufferPointer(start: senders, count: Int(count))).map { Int($0) }
            switch transport.transportImpl.receiveAll(senders: senderArray) {
            case .success(let dataArray):
                let totalSize = dataArray.reduce(0) { $0 + $1.count }
                let flatBuffer = malloc(totalSize)
                let sizeArray = malloc(Int(count) * MemoryLayout<Int32>.size)

                var offset = 0
                for (i, data) in dataArray.enumerated() {
                    if let basePtr = flatBuffer?.assumingMemoryBound(to: UInt8.self) {
                        _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: basePtr + offset, count: data.count))
                    }
                    (sizeArray! + i * MemoryLayout<Int32>.size).assumingMemoryBound(to: Int32.self).pointee = Int32(data.count)
                    offset += data.count
                }

                msgs.pointee.data = flatBuffer
                msgs.pointee.sizes = sizeArray?.assumingMemoryBound(to: Int32.self)
                msgs.pointee.count = Int32(count)
                return 0
            case .failure:
                return -1
            }
        }

        // Set the context pointer after all properties are initialized
        self.contextPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        callbacksPtr.deallocate()
    }
}

// MARK: Error Types

enum CBMPCError: Error, Equatable {
    case jobCreationFailed
    case keyGenerationFailed
    case signingFailed
    case keySerializationFailed
    case invalidKeyData
    case refreshFailed
    case verificationFailed
    case transportError(String)

    static func == (lhs: CBMPCError, rhs: CBMPCError) -> Bool {
        switch (lhs, rhs) {
        case (.jobCreationFailed, .jobCreationFailed),
             (.keyGenerationFailed, .keyGenerationFailed),
             (.signingFailed, .signingFailed),
             (.keySerializationFailed, .keySerializationFailed),
             (.invalidKeyData, .invalidKeyData),
             (.refreshFailed, .refreshFailed),
             (.verificationFailed, .verificationFailed):
            return true
        case (.transportError(let a), .transportError(let b)):
            return a == b
        default:
            return false
        }
    }
}
