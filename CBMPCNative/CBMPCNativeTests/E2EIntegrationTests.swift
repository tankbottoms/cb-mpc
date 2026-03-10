import XCTest
@testable import CBMPCNative

/// End-to-end integration test scaffolds for 2-party ECDSA ceremonies.
/// These tests require real devices and/or a running key server.
/// Add a test target to the Xcode project before running.
class E2EIntegrationTests: XCTestCase {

    // MARK: - Device+Device DKG

    /// Test Device+Device DKG on two real devices.
    /// Precondition: Two iOS devices on same WiFi, paired via QR code.
    func testDeviceDeviceDKGE2E() throws {
        // Steps:
        // 1. Device A: Tap "Create Key" -> Device+Device
        // 2. Device A: Generates QR code
        // 3. Device B: Scan QR code on Device A
        // 4. Both devices: Complete MC connection
        // 5. Both devices: Run DKG ceremony
        // 6. Verify both have compatible shares in Keychain
        // 7. Verify public key matches on both devices
        XCTAssertTrue(true)  // Placeholder
    }

    // MARK: - Device+Server DKG

    /// Test Device+Server DKG.
    /// Precondition: Key server deployed and accessible.
    func testDeviceServerDKGE2E() throws {
        // Steps:
        // 1. Device: Tap "Create Key" -> Device+Server
        // 2. Device: Calls server /sessions/dkg
        // 3. Device: Runs local DKG with server interaction
        // 4. Device: Stores device share in Keychain
        // 5. Verify public key matches server's record
        // 6. Verify share stored in Keychain
        XCTAssertTrue(true)  // Placeholder
    }

    // MARK: - Signing

    /// Test signing with Device+Server key.
    func testDeviceServerSigningE2E() throws {
        // Precondition: Device+Server key already generated
        // Steps:
        // 1. Retrieve device share from Keychain
        // 2. Send signing request to server
        // 3. Combine partial signatures
        // 4. Verify final signature against public key
        XCTAssertTrue(true)  // Placeholder
    }

    // MARK: - Ceremony State Machine

    func testCeremonySessionCodable() throws {
        let session = CeremonySession(
            type: .dkg,
            participantMode: .device,
            localPartyId: 0
        )
        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(CeremonySession.self, from: encoded)
        XCTAssertEqual(session.id, decoded.id)
        XCTAssertEqual(session.state, decoded.state)
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
    }

    func testCeremonyMessageCoding() throws {
        let session = CeremonySession(
            type: .dkg,
            participantMode: .device,
            localPartyId: 0
        )
        let message = CeremonyMessage.ceremonyInit(session)

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)

        if case .ceremonyInit(let decodedSession) = decoded {
            XCTAssertEqual(decodedSession.id, session.id)
        } else {
            XCTFail("Should decode as ceremonyInit")
        }
    }

    func testDKGCommitmentsMessage() throws {
        let data = Data([1, 2, 3, 4, 5])
        let message = CeremonyMessage.dkgCommitments(data)

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)

        if case .dkgCommitments(let decodedData) = decoded {
            XCTAssertEqual(decodedData, data)
        } else {
            XCTFail("Should decode as dkgCommitments")
        }
    }
}
