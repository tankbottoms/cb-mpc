import XCTest
@testable import CBMPCNative

/// Unit tests for PeerSigningCoordinator and Device+Device signing flow.
/// Uses mock-based tests since MultipeerConnectivity requires 2 physical devices.
@MainActor
class PeerSigningTests: XCTestCase {
    var ceremonyCoordinator: CeremonyCoordinator!
    var signingCoordinator: SigningCoordinator!

    override func setUp() {
        super.setUp()
        ceremonyCoordinator = CeremonyCoordinator()
        signingCoordinator = SigningCoordinator(ceremonyCoordinator: ceremonyCoordinator)
    }

    // MARK: - SigningCoordinator Device Signing Tests

    func testSignWithDeviceCreatesSigningCeremony() throws {
        // Verify that the ceremony is created with device participant mode
        let hash = Data(repeating: 0x42, count: 32)
        let ceremony = try ceremonyCoordinator.createSigningCeremony(
            participantMode: .device,
            localPartyId: 0,
            messageHash: hash
        )

        XCTAssertEqual(ceremony.type, .signing)
        XCTAssertEqual(ceremony.participantMode, .device)
        XCTAssertEqual(ceremony.localPartyId, 0)
        XCTAssertEqual(ceremony.messageHash, hash)
        XCTAssertNotNil(ceremonyCoordinator.activeCeremony)
    }

    func testSignWithDeviceCeremonyLifecycle() throws {
        // Test the full ceremony lifecycle for device signing
        let hash = Data(repeating: 0xAB, count: 32)
        let ceremony = try ceremonyCoordinator.createSigningCeremony(
            participantMode: .device,
            localPartyId: 1,
            messageHash: hash
        )

        // committed
        try ceremonyCoordinator.updateState(ceremonyId: ceremony.id, newState: .committed)
        XCTAssertEqual(ceremonyCoordinator.getCeremony(ceremony.id)?.state, .committed)

        // signed
        try ceremonyCoordinator.updateState(ceremonyId: ceremony.id, newState: .signed)
        XCTAssertEqual(ceremonyCoordinator.getCeremony(ceremony.id)?.state, .signed)

        // complete
        try ceremonyCoordinator.completeCeremony(
            ceremonyId: ceremony.id,
            publicKey: "02abcdef",
            shareId: ""
        )
        XCTAssertEqual(ceremonyCoordinator.getCeremony(ceremony.id)?.state, .complete)
        XCTAssertNil(ceremonyCoordinator.activeCeremony)
    }

    func testSignWithDeviceFailureClearsActiveCeremony() throws {
        let hash = Data(repeating: 0xCD, count: 32)
        let ceremony = try ceremonyCoordinator.createSigningCeremony(
            participantMode: .device,
            localPartyId: 0,
            messageHash: hash
        )

        try ceremonyCoordinator.updateState(ceremonyId: ceremony.id, newState: .committed)

        // Simulate failure
        try ceremonyCoordinator.failCeremony(
            ceremonyId: ceremony.id,
            error: "No connected peer"
        )

        XCTAssertNil(ceremonyCoordinator.activeCeremony, "Active ceremony should be cleared on failure")
        if case .failed(let msg) = ceremonyCoordinator.getCeremony(ceremony.id)?.state {
            XCTAssertEqual(msg, "No connected peer")
        } else {
            XCTFail("Ceremony should be in failed state")
        }
    }

    func testCannotCreateSecondCeremonyDuringActive() throws {
        let hash = Data(repeating: 0x11, count: 32)
        _ = try ceremonyCoordinator.createSigningCeremony(
            participantMode: .device,
            localPartyId: 0,
            messageHash: hash
        )

        XCTAssertThrowsError(
            try ceremonyCoordinator.createSigningCeremony(
                participantMode: .device,
                localPartyId: 1,
                messageHash: hash
            )
        ) { error in
            guard let coordError = error as? CeremonyCoordinator.CoordinatorError else {
                XCTFail("Expected CoordinatorError")
                return
            }
            if case .alreadyInProgress = coordError {
                // Expected
            } else {
                XCTFail("Expected alreadyInProgress error")
            }
        }
    }

    // MARK: - PeerSigningCoordinator Unit Tests

    func testPeerSignResultStructure() {
        // Verify PeerSignResult can be created
        let sig = Data([0x30, 0x44, 0x02, 0x20])
        let hash = Data(repeating: 0xAA, count: 32)
        let result = PeerSigningCoordinator.PeerSignResult(
            signature: sig,
            messageHash: hash
        )
        XCTAssertEqual(result.signature, sig)
        XCTAssertEqual(result.messageHash, hash)
    }

    // MARK: - KeyShareManager Integration

    func testShareRetrievalForSigning() async throws {
        let shareManager = KeyShareManager.shared
        let testKeyId = UUID()
        let testShare = Data(repeating: 0xBE, count: 128)

        // Store a share
        let share = try await shareManager.storeShare(
            shareBytes: testShare,
            keyId: testKeyId,
            partyId: 0,
            ceremonyType: "device_device",
            publicKey: "02test1234"
        )

        // Construct share ID same way SigningCoordinator does
        let expectedShareId = "cb-mpc.share.\(testKeyId.uuidString).0"
        XCTAssertEqual(share.id, expectedShareId)

        // Retrieve using the same pattern
        let retrieved = try await shareManager.retrieveShare(shareId: expectedShareId)
        XCTAssertEqual(retrieved, testShare)

        // Clean up
        try await shareManager.deleteShare(shareId: expectedShareId)
    }

    func testShareNotFoundThrows() async throws {
        let shareManager = KeyShareManager.shared
        let fakeId = "cb-mpc.share.\(UUID().uuidString).0"

        do {
            _ = try await shareManager.retrieveShare(shareId: fakeId)
            XCTFail("Should throw notFound")
        } catch let error as KeyShareManager.KeyShareError {
            if case .notFound = error {
                // Expected
            } else {
                XCTFail("Expected notFound, got \(error)")
            }
        }
    }

    // MARK: - CeremonyMessage Signing Tests

    func testSigningRequestMessageRoundTrip() throws {
        let messageHash = Data(repeating: 0xFF, count: 32)
        let message = CeremonyMessage.signingRequest(messageHash)

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)

        if case .signingRequest(let decodedHash) = decoded {
            XCTAssertEqual(decodedHash, messageHash)
        } else {
            XCTFail("Should decode as signingRequest")
        }
    }

    func testSigningResponseMessageRoundTrip() throws {
        let signature = Data([0x30, 0x45, 0x02, 0x21, 0x00])
        let message = CeremonyMessage.signingResponse(signature)

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)

        if case .signingResponse(let decodedSig) = decoded {
            XCTAssertEqual(decodedSig, signature)
        } else {
            XCTFail("Should decode as signingResponse")
        }
    }
}
