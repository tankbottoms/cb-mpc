import XCTest
@testable import CBMPCNative

class CeremonySessionTests: XCTestCase {
    func testCeremonySessionInit() {
        let session = CeremonySession(type: .dkg, participantMode: .device, localPartyId: 0)
        XCTAssertEqual(session.type, .dkg)
        XCTAssertEqual(session.participantMode, .device)
        XCTAssertEqual(session.localPartyId, 0)
        XCTAssertEqual(session.state, .initialized)
        XCTAssertNil(session.publicKey)
        XCTAssertNil(session.completedAt)
    }

    func testCeremonySessionCodable() throws {
        let session = CeremonySession(type: .dkg, participantMode: .device, localPartyId: 0)
        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(CeremonySession.self, from: encoded)
        XCTAssertEqual(session.id, decoded.id)
        XCTAssertEqual(session.type, decoded.type)
        XCTAssertEqual(session.participantMode, decoded.participantMode)
        XCTAssertEqual(session.localPartyId, decoded.localPartyId)
        XCTAssertEqual(session.state, decoded.state)
    }

    func testSigningSessionCodable() throws {
        var session = CeremonySession(type: .signing, participantMode: .server, localPartyId: 0)
        session.messageHash = Data([1, 2, 3, 4])
        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(CeremonySession.self, from: encoded)
        XCTAssertEqual(decoded.type, .signing)
        XCTAssertEqual(decoded.participantMode, .server)
        XCTAssertEqual(decoded.messageHash, Data([1, 2, 3, 4]))
    }

    func testCeremonyStateCodable() throws {
        let states: [CeremonyState] = [.initialized, .committed, .signed, .complete, .failed("test error")]
        for state in states {
            let encoded = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(CeremonyState.self, from: encoded)
            XCTAssertEqual(state, decoded)
        }
    }

    func testCeremonyStateFailedPreservesMessage() throws {
        let state = CeremonyState.failed("Network timeout after 30s")
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CeremonyState.self, from: encoded)
        if case .failed(let msg) = decoded {
            XCTAssertEqual(msg, "Network timeout after 30s")
        } else {
            XCTFail("Expected .failed state")
        }
    }

    func testKeyShareCodable() throws {
        let share = KeyShare(
            id: "cb-mpc.share.test.0",
            keyId: UUID(),
            partyId: 0,
            ceremonyType: "device_device",
            createdAt: Date(),
            publicKey: "02abcd1234"
        )
        let encoded = try JSONEncoder().encode(share)
        let decoded = try JSONDecoder().decode(KeyShare.self, from: encoded)
        XCTAssertEqual(share.id, decoded.id)
        XCTAssertEqual(share.partyId, decoded.partyId)
        XCTAssertEqual(share.ceremonyType, decoded.ceremonyType)
        XCTAssertEqual(share.publicKey, decoded.publicKey)
    }

    func testKeyShareDefaultValues() throws {
        let share = KeyShare(
            id: "test",
            keyId: UUID(),
            partyId: 1,
            ceremonyType: "device_server",
            createdAt: Date(),
            publicKey: "03ef"
        )
        XCTAssertNil(share.backupTokenUSBC)
        XCTAssertFalse(share.iCloudBackedUp)
    }

    func testCeremonyTypeCodable() throws {
        let types: [CeremonyType] = [.dkg, .signing]
        for type in types {
            let encoded = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(CeremonyType.self, from: encoded)
            XCTAssertEqual(type, decoded)
        }
    }

    func testParticipantModeCodable() throws {
        let modes: [ParticipantMode] = [.device, .server]
        for mode in modes {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(ParticipantMode.self, from: encoded)
            XCTAssertEqual(mode, decoded)
        }
    }
}
