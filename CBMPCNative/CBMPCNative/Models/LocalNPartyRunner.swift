import Foundation

/// Thread-safe message queue for N-party transport
private class MPMessageQueue {
    private var messages: [Data] = []
    private let condition = NSCondition()
    private var aborted = false

    func enqueue(_ data: Data) {
        condition.lock()
        messages.append(data)
        condition.signal()
        condition.unlock()
    }

    func dequeue() -> Data? {
        condition.lock()
        defer { condition.unlock() }
        while messages.isEmpty && !aborted {
            condition.wait()
        }
        if aborted { return nil }
        return messages.removeFirst()
    }

    func abort() {
        condition.lock()
        aborted = true
        condition.broadcast()
        condition.unlock()
    }
}

/// N-party transport: each party has incoming queues from every other party
private class NPartyTransport {
    let roleIndex: Int
    let partyCount: Int
    var incomingQueues: [Int: MPMessageQueue] = [:]
    var peers: [Int: NPartyTransport] = [:]

    init(roleIndex: Int, partyCount: Int) {
        self.roleIndex = roleIndex
        self.partyCount = partyCount
        for i in 0..<partyCount where i != roleIndex {
            incomingQueues[i] = MPMessageQueue()
        }
    }

    func abort() {
        for queue in incomingQueues.values { queue.abort() }
    }
}

/// Adapter implementing CBMPCTransportInterface for one party in an N-party setting
class LocalNPartyTransportAdapter: CBMPCTransportInterface {
    private let party: NPartyTransport

    fileprivate init(party: NPartyTransport) {
        self.party = party
    }

    func send(receiver: Int, message: Data) -> Int {
        guard let peer = party.peers[receiver] else { return -1 }
        guard let queue = peer.incomingQueues[party.roleIndex] else { return -1 }
        queue.enqueue(message)
        return 0
    }

    func receive(sender: Int) -> Result<Data, CBMPCError> {
        guard let queue = party.incomingQueues[sender] else {
            return .failure(.transportError("No queue for sender \(sender)"))
        }
        guard let data = queue.dequeue() else {
            return .failure(.transportError("Transport aborted"))
        }
        return .success(data)
    }

    func receiveAll(senders: [Int]) -> Result<[Data], CBMPCError> {
        let group = DispatchGroup()
        var results = [Int: Data]()
        let lock = NSLock()
        var receiveError: CBMPCError?

        for sender in senders {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                switch self.receive(sender: sender) {
                case .success(let data):
                    lock.lock()
                    results[sender] = data
                    lock.unlock()
                case .failure(let error):
                    lock.lock()
                    receiveError = error
                    lock.unlock()
                }
            }
        }

        group.wait()

        if let error = receiveError { return .failure(error) }
        let ordered = senders.compactMap { results[$0] }
        guard ordered.count == senders.count else {
            return .failure(.transportError("Missing messages from some senders"))
        }
        return .success(ordered)
    }
}

/// Runs an N-party MPC protocol locally by executing all parties on concurrent threads
class LocalNPartyRunner {

    /// Run an N-party protocol concurrently for all parties
    /// Returns array of results indexed by party role
    static func run<T>(
        partyCount: Int,
        partyNames: [String],
        operation: @escaping (CBMPCJobMP, Int) throws -> T
    ) throws -> [T] {
        // Create transports for all parties
        let parties = (0..<partyCount).map { NPartyTransport(roleIndex: $0, partyCount: partyCount) }

        // Connect all peers
        for i in 0..<partyCount {
            for j in 0..<partyCount where j != i {
                parties[i].peers[j] = parties[j]
            }
        }

        let adapters = parties.map { LocalNPartyTransportAdapter(party: $0) }

        var results = [Int: T]()
        var errors = [Int: Error]()
        let lock = NSLock()
        let group = DispatchGroup()

        for i in 0..<partyCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                do {
                    let transport = try CBMPCTransport(adapters[i])
                    let job = try CBMPCJobMP(partyCount: partyCount, role: i,
                                             partyNames: partyNames, transport: transport)
                    let result = try operation(job, i)
                    lock.lock()
                    results[i] = result
                    lock.unlock()
                } catch {
                    lock.lock()
                    errors[i] = error
                    lock.unlock()
                    // Abort all parties on error
                    for p in parties { p.abort() }
                }
            }
        }

        group.wait()

        if let firstError = errors.values.first {
            throw firstError
        }

        // Collect results in order
        return (0..<partyCount).compactMap { results[$0] }
    }
}
