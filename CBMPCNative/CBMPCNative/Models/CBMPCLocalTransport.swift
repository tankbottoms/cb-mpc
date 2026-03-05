import Foundation

/// Thread-safe message queue for one party's incoming messages from another party.
/// Uses NSCondition for blocking receive (matching the Go MockMessenger pattern).
private class MessageQueue {
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

/// A party's view of the transport - receives messages from other parties.
/// Each party has its own set of incoming queues (one per sender).
private class PartyTransport {
    let roleIndex: Int
    /// Incoming queues indexed by sender role
    var incomingQueues: [Int: MessageQueue] = [:]
    /// Reference to the other party's transport (for sending)
    weak var peerTransport: PartyTransport?

    init(roleIndex: Int, partyCount: Int) {
        self.roleIndex = roleIndex
        for i in 0..<partyCount where i != roleIndex {
            incomingQueues[i] = MessageQueue()
        }
    }

    func abort() {
        for queue in incomingQueues.values {
            queue.abort()
        }
    }
}

/// Transport that connects two parties running on separate threads.
/// Implements the CBMPCTransportInterface for one party.
class LocalPartyTransportAdapter: CBMPCTransportInterface {
    private let party: PartyTransport

    fileprivate init(party: PartyTransport) {
        self.party = party
    }

    func send(receiver: Int, message: Data) -> Int {
        // Send to receiver's incoming queue from our role
        guard let peer = party.peerTransport else { return -1 }
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
        // Receive from each sender concurrently (matching Go pattern)
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

        if let error = receiveError {
            return .failure(error)
        }

        let ordered = senders.compactMap { results[$0] }
        guard ordered.count == senders.count else {
            return .failure(.transportError("Missing messages from some senders"))
        }
        return .success(ordered)
    }
}

/// Runs a 2-party MPC protocol locally by executing both parties on concurrent threads.
/// This mirrors the Go MPCRunner.MPCRun2P() pattern.
class LocalTwoPartyRunner {

    struct PartyResult {
        let role: Int
        let error: CBMPCError?
    }

    /// Run a 2-party protocol function concurrently for both parties.
    /// The function receives a CBMPCJob and should perform the protocol operation.
    /// Returns results from both parties.
    static func run<T>(
        partyNames: [String] = ["Local", "Remote"],
        operation: @escaping (CBMPCJob, Int) throws -> T
    ) throws -> (T, T) {
        let party0 = PartyTransport(roleIndex: 0, partyCount: 2)
        let party1 = PartyTransport(roleIndex: 1, partyCount: 2)
        party0.peerTransport = party1
        party1.peerTransport = party0

        let adapter0 = LocalPartyTransportAdapter(party: party0)
        let adapter1 = LocalPartyTransportAdapter(party: party1)

        var result0: T?
        var result1: T?
        var error0: Error?
        var error1: Error?

        let group = DispatchGroup()

        // Party 0
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            do {
                let transport = try CBMPCTransport(adapter0)
                let job = try CBMPCJob(role: .party1, partyNames: partyNames, transport: transport)
                result0 = try operation(job, 0)
            } catch {
                error0 = error
                party0.abort()
                party1.abort()
            }
        }

        // Party 1
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            do {
                let transport = try CBMPCTransport(adapter1)
                let job = try CBMPCJob(role: .party2, partyNames: partyNames, transport: transport)
                result1 = try operation(job, 1)
            } catch {
                error1 = error
                party0.abort()
                party1.abort()
            }
        }

        group.wait()

        if let err = error0 {
            throw err
        }
        if let err = error1 {
            throw err
        }

        guard let r0 = result0, let r1 = result1 else {
            throw CBMPCError.jobCreationFailed
        }

        return (r0, r1)
    }
}
