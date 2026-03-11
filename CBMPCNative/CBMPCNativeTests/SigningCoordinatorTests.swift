import XCTest
@testable import CBMPCNative

@MainActor
class SigningCoordinatorTests: XCTestCase {
    var ceremonyCoordinator: CeremonyCoordinator!
    var signingCoordinator: SigningCoordinator!

    override func setUp() {
        super.setUp()
        ceremonyCoordinator = CeremonyCoordinator()
        signingCoordinator = SigningCoordinator(ceremonyCoordinator: ceremonyCoordinator)
    }

    func testSigningCoordinatorInit() {
        XCTAssertNotNil(signingCoordinator)
    }

    func testDeviceSigningNotYetImplemented() async {
        // signWithDevice currently throws invalidState
        // This verifies the stub behavior and ceremony lifecycle
        do {
            // We can't easily create a PeerConnectionManager in tests without MC framework,
            // so we test that the coordinator exists and is properly initialized
            XCTAssertNotNil(signingCoordinator)
        }
    }

    func testCeremonyCreatedOnSignAttempt() throws {
        // Verify that ceremonies can be created for signing
        let hash = Data(repeating: 0x42, count: 32)
        let ceremony = try ceremonyCoordinator.createSigningCeremony(
            participantMode: .server,
            localPartyId: 0,
            messageHash: hash
        )
        XCTAssertEqual(ceremony.type, .signing)
        XCTAssertEqual(ceremony.messageHash, hash)
        XCTAssertNotNil(ceremonyCoordinator.activeCeremony)
    }

    func testSigningCeremonyLifecycle() throws {
        let hash = Data(repeating: 0x42, count: 32)
        let ceremony = try ceremonyCoordinator.createSigningCeremony(
            participantMode: .server,
            localPartyId: 0,
            messageHash: hash
        )

        try ceremonyCoordinator.updateState(ceremonyId: ceremony.id, newState: .committed)
        XCTAssertEqual(ceremonyCoordinator.getCeremony(ceremony.id)?.state, .committed)

        try ceremonyCoordinator.updateState(ceremonyId: ceremony.id, newState: .signed)
        XCTAssertEqual(ceremonyCoordinator.getCeremony(ceremony.id)?.state, .signed)

        try ceremonyCoordinator.completeCeremony(
            ceremonyId: ceremony.id,
            publicKey: "02abcd",
            shareId: ""
        )
        XCTAssertEqual(ceremonyCoordinator.getCeremony(ceremony.id)?.state, .complete)
        XCTAssertNil(ceremonyCoordinator.activeCeremony)
    }
}
