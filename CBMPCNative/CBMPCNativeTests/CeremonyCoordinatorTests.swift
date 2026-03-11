import XCTest
@testable import CBMPCNative

@MainActor
class CeremonyCoordinatorTests: XCTestCase {
    var coordinator: CeremonyCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = CeremonyCoordinator()
    }

    func testCreateDKGCeremony() throws {
        let session = try coordinator.createDKGCeremony(participantMode: .device, localPartyId: 0)
        XCTAssertEqual(session.type, .dkg)
        XCTAssertEqual(session.participantMode, .device)
        XCTAssertEqual(session.localPartyId, 0)
        XCTAssertEqual(session.state, .initialized)
        XCTAssertNotNil(coordinator.activeCeremony)
        XCTAssertEqual(coordinator.ceremonies.count, 1)
    }

    func testCreateSigningCeremony() throws {
        let hash = Data([1, 2, 3])
        let session = try coordinator.createSigningCeremony(participantMode: .server, localPartyId: 0, messageHash: hash)
        XCTAssertEqual(session.type, .signing)
        XCTAssertEqual(session.participantMode, .server)
        XCTAssertEqual(session.messageHash, hash)
    }

    func testCannotCreateSecondCeremony() throws {
        _ = try coordinator.createDKGCeremony(participantMode: .device, localPartyId: 0)
        XCTAssertThrowsError(try coordinator.createDKGCeremony(participantMode: .device, localPartyId: 1)) { error in
            XCTAssertTrue(error is CeremonyCoordinator.CoordinatorError)
        }
    }

    func testUpdateState() throws {
        let session = try coordinator.createDKGCeremony(participantMode: .device, localPartyId: 0)
        try coordinator.updateState(ceremonyId: session.id, newState: .committed)
        let updated = coordinator.getCeremony(session.id)
        XCTAssertEqual(updated?.state, .committed)
    }

    func testUpdateStateNotFound() {
        XCTAssertThrowsError(try coordinator.updateState(ceremonyId: UUID(), newState: .committed))
    }

    func testCompleteCeremony() throws {
        let session = try coordinator.createDKGCeremony(participantMode: .device, localPartyId: 0)
        try coordinator.completeCeremony(ceremonyId: session.id, publicKey: "02abcd", shareId: "share.0")
        let completed = coordinator.getCeremony(session.id)
        XCTAssertEqual(completed?.state, .complete)
        XCTAssertEqual(completed?.publicKey, "02abcd")
        XCTAssertEqual(completed?.shareId, "share.0")
        XCTAssertNotNil(completed?.completedAt)
        XCTAssertNil(coordinator.activeCeremony)
    }

    func testFailCeremony() throws {
        let session = try coordinator.createDKGCeremony(participantMode: .device, localPartyId: 0)
        try coordinator.failCeremony(ceremonyId: session.id, error: "test failure")
        let failed = coordinator.getCeremony(session.id)
        XCTAssertEqual(failed?.state, .failed("test failure"))
        XCTAssertEqual(failed?.error, "test failure")
        XCTAssertNil(coordinator.activeCeremony)
    }

    func testCanCreateNewCeremonyAfterCompletion() throws {
        let first = try coordinator.createDKGCeremony(participantMode: .device, localPartyId: 0)
        try coordinator.completeCeremony(ceremonyId: first.id, publicKey: "02ab", shareId: "s1")
        let second = try coordinator.createDKGCeremony(participantMode: .server, localPartyId: 0)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(coordinator.ceremonies.count, 2)
    }

    func testCanCreateNewCeremonyAfterFailure() throws {
        let first = try coordinator.createDKGCeremony(participantMode: .device, localPartyId: 0)
        try coordinator.failCeremony(ceremonyId: first.id, error: "err")
        let second = try coordinator.createDKGCeremony(participantMode: .device, localPartyId: 0)
        XCTAssertNotNil(second)
    }

    func testFullLifecycle() throws {
        let session = try coordinator.createDKGCeremony(participantMode: .device, localPartyId: 0)
        XCTAssertEqual(session.state, .initialized)

        try coordinator.updateState(ceremonyId: session.id, newState: .committed)
        XCTAssertEqual(coordinator.getCeremony(session.id)?.state, .committed)

        try coordinator.updateState(ceremonyId: session.id, newState: .signed)
        XCTAssertEqual(coordinator.getCeremony(session.id)?.state, .signed)

        try coordinator.completeCeremony(ceremonyId: session.id, publicKey: "02ef", shareId: "s")
        XCTAssertEqual(coordinator.getCeremony(session.id)?.state, .complete)
    }
}
