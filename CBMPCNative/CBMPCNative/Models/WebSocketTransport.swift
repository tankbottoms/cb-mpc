import Foundation

/// WebSocket-based transport implementing CBMPCTransportInterface.
/// Bridges async WebSocket I/O to the synchronous send/receive calls
/// expected by the C++ MPC library via NSCondition-guarded queues.
class WebSocketTransport: CBMPCTransportInterface {
    private let url: URL
    private let partyId: UInt16
    private let sessionPrefix: Data

    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession

    /// Per-sender incoming message queues, guarded by NSCondition for blocking receive
    private var inboxes: [UInt16: IncomingQueue] = [:]
    private let inboxLock = NSLock()

    private var isConnected = false
    private var receiveLoopTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    init(url: URL, partyId: UInt16, sessionPrefix: Data) {
        self.url = url
        self.partyId = partyId
        self.sessionPrefix = sessionPrefix
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Connection

    func connect() async throws {
        let task = session.webSocketTask(with: url)
        task.resume()
        self.webSocketTask = task
        self.isConnected = true

        // Start background receive loop
        receiveLoopTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        // Start keepalive pings
        pingTask = Task { [weak self] in
            await self?.pingLoop()
        }
    }

    func disconnect() {
        isConnected = false
        receiveLoopTask?.cancel()
        pingTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)

        // Abort all waiting receivers
        inboxLock.lock()
        for (_, queue) in inboxes {
            queue.abort()
        }
        inboxLock.unlock()
    }

    // MARK: - CBMPCTransportInterface

    func send(receiver: Int, message: Data) -> Int {
        let encoded = MPCProtocol.encode(
            type: MPCProtocol.MSG_TYPE_DKG_MSG, // Default; overridden by caller context
            sessionPrefix: sessionPrefix,
            senderPartyId: partyId,
            receiverPartyId: UInt16(receiver),
            payload: message
        )

        let semaphore = DispatchSemaphore(value: 0)
        var sendResult = 0

        webSocketTask?.send(.data(encoded)) { error in
            if error != nil { sendResult = -1 }
            semaphore.signal()
        }

        semaphore.wait()
        return sendResult
    }

    func receive(sender: Int) -> Result<Data, CBMPCError> {
        let queue = getOrCreateQueue(for: UInt16(sender))
        guard let data = queue.dequeue() else {
            return .failure(.transportError("WebSocket receive aborted"))
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

        if let error = receiveError {
            return .failure(error)
        }

        let ordered = senders.compactMap { results[$0] }
        guard ordered.count == senders.count else {
            return .failure(.transportError("Missing messages from some senders"))
        }
        return .success(ordered)
    }

    // MARK: - Raw Send (for protocol-level messages like DKG_COMPLETE)

    func sendRaw(_ data: Data) {
        let semaphore = DispatchSemaphore(value: 0)
        webSocketTask?.send(.data(data)) { _ in semaphore.signal() }
        semaphore.wait()
    }

    // MARK: - Background Receive Loop

    private func receiveLoop() async {
        guard let ws = webSocketTask else { return }

        while isConnected && !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case .data(let data):
                    handleIncomingData(data)
                case .string(let text):
                    // Handle JSON control messages (pong, etc.)
                    handleControlMessage(text)
                @unknown default:
                    break
                }
            } catch {
                if isConnected {
                    isConnected = false
                    // Abort all queues on connection error
                    inboxLock.lock()
                    for (_, queue) in inboxes {
                        queue.abort()
                    }
                    inboxLock.unlock()
                }
                break
            }
        }
    }

    private func handleIncomingData(_ data: Data) {
        guard let msg = MPCProtocol.decode(data) else { return }

        // Only process messages addressed to us or broadcast
        guard msg.receiverPartyId == partyId || msg.receiverPartyId == MPCProtocol.broadcastReceiver else {
            return
        }

        let queue = getOrCreateQueue(for: msg.senderPartyId)
        queue.enqueue(msg.payload)
    }

    private func handleControlMessage(_ text: String) {
        // JSON control messages like {"type":"pong"} — no action needed
    }

    // MARK: - Keepalive

    private func pingLoop() async {
        while isConnected && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            guard isConnected else { break }
            let pingJSON = Data("{\"type\":\"ping\"}".utf8)
            webSocketTask?.send(.string(String(data: pingJSON, encoding: .utf8) ?? "")) { _ in }
        }
    }

    // MARK: - Queue Management

    private func getOrCreateQueue(for sender: UInt16) -> IncomingQueue {
        inboxLock.lock()
        defer { inboxLock.unlock() }

        if let existing = inboxes[sender] {
            return existing
        }
        let queue = IncomingQueue()
        inboxes[sender] = queue
        return queue
    }
}

// MARK: - Incoming Queue (NSCondition-based, matches LocalTwoPartyRunner's MessageQueue)

private class IncomingQueue {
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
