import Foundation

// MARK: - Ceremony Enums

enum CeremonyType: String, Codable {
    case dkg
    case signing
}

enum ParticipantMode: String, Codable {
    case device
    case server
}

enum CeremonyState: Equatable, Codable {
    case initialized
    case committed
    case signed
    case complete
    case failed(String)

    // MARK: - Custom Codable conformance for associated-value case

    private enum CodingKeys: String, CodingKey {
        case type
        case message
    }

    private enum StateType: String, Codable {
        case initialized
        case committed
        case signed
        case complete
        case failed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stateType = try container.decode(StateType.self, forKey: .type)

        switch stateType {
        case .initialized:
            self = .initialized
        case .committed:
            self = .committed
        case .signed:
            self = .signed
        case .complete:
            self = .complete
        case .failed:
            let message = try container.decode(String.self, forKey: .message)
            self = .failed(message)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .initialized:
            try container.encode(StateType.initialized, forKey: .type)
        case .committed:
            try container.encode(StateType.committed, forKey: .type)
        case .signed:
            try container.encode(StateType.signed, forKey: .type)
        case .complete:
            try container.encode(StateType.complete, forKey: .type)
        case .failed(let message):
            try container.encode(StateType.failed, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

// MARK: - CeremonySession

struct CeremonySession: Identifiable, Codable {
    let id: UUID
    let type: CeremonyType
    let participantMode: ParticipantMode
    var localPartyId: Int  // 0 or 1

    var state: CeremonyState
    var error: String?
    var startedAt: Date
    var completedAt: Date?

    // DKG-specific
    var publicKey: String?  // hex-encoded compressed pubkey
    var shareId: String?  // keychain identifier

    // Signing-specific
    var messageHash: Data?
    var signature: String?  // base64-encoded r||s
    var remoteContribution: Data?  // partial sig from peer/server

    init(
        id: UUID = UUID(),
        type: CeremonyType,
        participantMode: ParticipantMode,
        localPartyId: Int
    ) {
        self.id = id
        self.type = type
        self.participantMode = participantMode
        self.localPartyId = localPartyId
        self.state = .initialized
        self.startedAt = Date()
    }
}

// MARK: - KeyShare (Keychain storage metadata)

struct KeyShare: Identifiable, Codable {
    let id: String  // cb-mpc.share.{keyId}.{partyId}
    let keyId: UUID
    let partyId: Int
    let ceremonyType: String  // "device_device" or "device_server"
    let createdAt: Date
    let publicKey: String  // hex, for verification

    var backupTokenUSBC: String?
    var iCloudBackedUp: Bool = false
}
