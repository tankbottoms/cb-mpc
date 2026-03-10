import Foundation
import MultipeerConnectivity

/// MultipeerConnectivity-based transport implementing CBMPCTransportInterface.
/// Wraps an existing MCSession from the device pairing flow.
/// Uses NSCondition-guarded queues for blocking receive, same pattern as
/// WebSocketTransport and LocalTwoPartyRunner's MessageQueue.
class MultipeerTransport: NSObject, CBMPCTransportInterface, MCSessionDelegate {
    private let mcSession: MCSession
    private let localPartyId: UInt16
    private let remotePeerID: MCPeerID

    /// Per-sender incoming message queues
    private var inboxes: [UInt16: PeerMessageQueue] = [:]
    private let inboxLock = NSLock()

    init(session: MCSession, localPartyId: UInt16, remotePeerID: MCPeerID) {
        self.mcSession = session
        self.localPartyId = localPartyId
        self.remotePeerID = remotePeerID
        super.init()
        self.mcSession.delegate = self
    }

    // MARK: - CBMPCTransportInterface

    func send(receiver: Int, message: Data) -> Int {
        do {
            try mcSession.send(message, toPeers: [remotePeerID], with: .reliable)
            return 0
        } catch {
            return -1
        }
    }

    func receive(sender: Int) -> Result<Data, CBMPCError> {
        let queue = getOrCreateQueue(for: UInt16(sender))
        guard let data = queue.dequeue() else {
            return .failure(.transportError("MultipeerConnectivity receive aborted"))
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

    func abort() {
        inboxLock.lock()
        for (_, queue) in inboxes {
            queue.abort()
        }
        inboxLock.unlock()
    }

    // MARK: - MCSessionDelegate

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Route all incoming data to the remote party's queue
        // In 2-party MPC, the remote party has the opposite party ID
        let remotePartyId: UInt16 = (localPartyId == 0) ? 1 : 0
        let queue = getOrCreateQueue(for: remotePartyId)
        queue.enqueue(data)
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        if state == .notConnected {
            abort()
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // MARK: - Queue Management

    private func getOrCreateQueue(for sender: UInt16) -> PeerMessageQueue {
        inboxLock.lock()
        defer { inboxLock.unlock() }
        if let existing = inboxes[sender] { return existing }
        let queue = PeerMessageQueue()
        inboxes[sender] = queue
        return queue
    }
}

// MARK: - Message Queue

private class PeerMessageQueue {
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
        while messages.isEmpty && !aborted { condition.wait() }
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
