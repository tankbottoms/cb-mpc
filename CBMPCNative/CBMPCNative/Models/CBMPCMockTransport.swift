import Foundation

/// Mock transport for local MPC testing without network
class CBMPCMockTransport: CBMPCTransportInterface {
    private var messageQueues: [Int: [Data]] = [:]
    private let lock = NSLock()

    init() {
        messageQueues[0] = []
        messageQueues[1] = []
    }

    /// Send message to party (stores in their queue)
    func send(receiver: Int, message: Data) -> Int {
        lock.lock()
        defer { lock.unlock() }

        if messageQueues[receiver] != nil {
            messageQueues[receiver]?.append(message)
            return 0
        }
        return -1
    }

    /// Receive message from party (retrieves from their queue)
    func receive(sender: Int) -> Result<Data, CBMPCError> {
        lock.lock()
        defer { lock.unlock() }

        guard var queue = messageQueues[sender], !queue.isEmpty else {
            return .failure(.transportError("No message from party \(sender)"))
        }

        let message = queue.removeFirst()
        messageQueues[sender] = queue
        return .success(message)
    }

    /// Receive from multiple parties
    func receiveAll(senders: [Int]) -> Result<[Data], CBMPCError> {
        lock.lock()
        defer { lock.unlock() }

        var messages: [Data] = []
        var updatedQueues = messageQueues

        for sender in senders {
            guard var queue = updatedQueues[sender], !queue.isEmpty else {
                return .failure(.transportError("No message from party \(sender)"))
            }
            messages.append(queue.removeFirst())
            updatedQueues[sender] = queue
        }

        messageQueues = updatedQueues
        return .success(messages)
    }

    /// Simulate two-party coordination locally
    static func simulateCoordination(
        party1: (CBMPCJob) -> Result<Void, CBMPCError>,
        party2: (CBMPCJob) -> Result<Void, CBMPCError>
    ) -> Result<Void, CBMPCError> {
        let transport = CBMPCMockTransport()

        // Run both parties' operations in sequence
        // In real scenario, these would be on different devices/threads
        do {
            let wrappedTransport = try CBMPCTransport(transport)
            let job1 = try CBMPCJob(role: .party1, partyNames: ["Party1", "Party2"], transport: wrappedTransport)
            let job2 = try CBMPCJob(role: .party2, partyNames: ["Party1", "Party2"], transport: wrappedTransport)

            // Execute party 1
            switch party1(job1) {
            case .success:
                break
            case .failure(let error):
                return .failure(error)
            }

            // Execute party 2
            switch party2(job2) {
            case .success:
                break
            case .failure(let error):
                return .failure(error)
            }

            return .success(())
        } catch {
            return .failure(.jobCreationFailed)
        }
    }
}
