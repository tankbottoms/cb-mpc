import Foundation
import Combine

@MainActor
class CeremonyCoordinator: ObservableObject {
    @Published var activeCeremony: CeremonySession?
    @Published var ceremonies: [CeremonySession] = []

    private let keyShareManager = KeyShareManager.shared

    enum CoordinatorError: LocalizedError {
        case invalidState(String)
        case timeout(String)
        case alreadyInProgress
        case notFound

        var errorDescription: String? {
            switch self {
            case .invalidState(let msg): return "Invalid ceremony state: \(msg)"
            case .timeout(let msg): return "Ceremony timeout: \(msg)"
            case .alreadyInProgress: return "Ceremony already in progress"
            case .notFound: return "Ceremony not found"
            }
        }
    }

    func createDKGCeremony(
        participantMode: ParticipantMode,
        localPartyId: Int
    ) throws -> CeremonySession {
        if activeCeremony != nil {
            throw CoordinatorError.alreadyInProgress
        }

        let session = CeremonySession(
            type: .dkg,
            participantMode: participantMode,
            localPartyId: localPartyId
        )

        activeCeremony = session
        ceremonies.append(session)
        return session
    }

    func createSigningCeremony(
        participantMode: ParticipantMode,
        localPartyId: Int,
        messageHash: Data
    ) throws -> CeremonySession {
        if activeCeremony != nil {
            throw CoordinatorError.alreadyInProgress
        }

        var session = CeremonySession(
            type: .signing,
            participantMode: participantMode,
            localPartyId: localPartyId
        )
        session.messageHash = messageHash

        activeCeremony = session
        ceremonies.append(session)
        return session
    }

    func updateState(ceremonyId: UUID, newState: CeremonyState) throws {
        guard let index = ceremonies.firstIndex(where: { $0.id == ceremonyId }) else {
            throw CoordinatorError.notFound
        }

        ceremonies[index].state = newState

        if ceremonies[index].id == activeCeremony?.id {
            activeCeremony?.state = newState
        }
    }

    func completeCeremony(
        ceremonyId: UUID,
        publicKey: String,
        shareId: String
    ) throws {
        guard let index = ceremonies.firstIndex(where: { $0.id == ceremonyId }) else {
            throw CoordinatorError.notFound
        }

        ceremonies[index].state = .complete
        ceremonies[index].completedAt = Date()
        ceremonies[index].publicKey = publicKey
        ceremonies[index].shareId = shareId

        if activeCeremony?.id == ceremonyId {
            activeCeremony = nil
        }
    }

    func failCeremony(ceremonyId: UUID, error: String) throws {
        guard let index = ceremonies.firstIndex(where: { $0.id == ceremonyId }) else {
            throw CoordinatorError.notFound
        }

        ceremonies[index].state = .failed(error)
        ceremonies[index].error = error

        if activeCeremony?.id == ceremonyId {
            activeCeremony = nil
        }
    }

    func getCeremony(_ ceremonyId: UUID) -> CeremonySession? {
        ceremonies.first { $0.id == ceremonyId }
    }
}
