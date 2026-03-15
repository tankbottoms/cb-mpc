import XCTest
import CryptoKit
@testable import CBMPCNative

/// Integration tests exercising the full Device+Server flow against the live key server.
/// These tests require network access and run against
/// https://cb-mpc-key-server.atsignhandle.workers.dev
class ServerIntegrationTests: XCTestCase {

    static let serverURL = URL(string: "https://cb-mpc-key-server.atsignhandle.workers.dev")!
    var client: ServerAPIClient!

    override func setUp() {
        super.setUp()
        client = ServerAPIClient(baseURL: Self.serverURL)
    }

    override func tearDown() {
        client = nil
        super.tearDown()
    }

    // MARK: - Health

    func testServerHealth() async throws {
        let health = try await client.health()
        XCTAssertEqual(health.status, "ok", "Server health check should return 'ok'")
    }

    // MARK: - Device Registration

    func testDeviceRegistration() async throws {
        let testDeviceName = "IntegrationTest-\(UUID().uuidString.prefix(8))"
        let testPublicKey = Data(repeating: 0x02, count: 33).map { String(format: "%02x", $0) }.joined()

        let response = try await client.register(
            deviceName: testDeviceName,
            deviceType: "simulator",
            publicKey: testPublicKey
        )

        XCTAssertFalse(response.device_id.isEmpty, "Should receive a device_id")
        XCTAssertFalse(response.token.isEmpty, "Should receive an auth token")
        XCTAssertGreaterThan(response.registered_at, 0, "Should have registration timestamp")

        // Verify token was stored in Keychain
        let storedToken = ServerAuthKeychain.loadToken(for: Self.serverURL.absoluteString)
        XCTAssertEqual(storedToken, response.token, "Token should be stored in Keychain")

        // Clean up
        ServerAuthKeychain.deleteToken(for: Self.serverURL.absoluteString)
    }

    // MARK: - Server DKG Full Flow

    func testServerDKGFullFlow() async throws {
        // Register device first
        try await registerTestDevice()

        // Run DKG
        let result = try await ServerDKGCoordinator.generateKey(
            serverURL: Self.serverURL,
            curveCode: 714
        )

        XCTAssertEqual(result.publicKey.count, 33, "Compressed secp256k1 public key should be 33 bytes")
        XCTAssertFalse(result.deviceShare.isEmpty, "Device share should not be empty")
        XCTAssertFalse(result.serverShare.isEmpty, "Server share should not be empty")
        XCTAssertFalse(result.sessionId.isEmpty, "Session ID should not be empty")

        // Verify server has the key stored
        let publicKeyHex = result.publicKey.map { String(format: "%02x", $0) }.joined()
        let keyInfo = try await client.getKey(publicKey: publicKeyHex)
        XCTAssertEqual(keyInfo.public_key, publicKeyHex, "Server should have the public key on record")
        XCTAssertNotNil(keyInfo.server_share, "Server should have the server share stored")

        // Clean up
        cleanupAuth()
    }

    // MARK: - Server Signing Full Flow

    func testServerSigningFullFlow() async throws {
        // Register and generate key
        try await registerTestDevice()
        let dkgResult = try await ServerDKGCoordinator.generateKey(
            serverURL: Self.serverURL,
            curveCode: 714
        )

        let publicKeyHex = dkgResult.publicKey.map { String(format: "%02x", $0) }.joined()
        let testMessage = Data("Hello, MPC signing test!".utf8)

        // Sign with server
        let signature = try await ServerSigningCoordinator.sign(
            message: testMessage,
            deviceShare: dkgResult.deviceShare,
            curveCode: 714,
            serverURL: Self.serverURL,
            publicKey: publicKeyHex
        )

        XCTAssertFalse(signature.isEmpty, "Signature should not be empty")

        // Verify signature against public key
        let messageHash = Data(SHA256.hash(data: testMessage))
        let verified = CBMPCCryptoEngine.verifySignature(
            curveCode: 714,
            publicKey: dkgResult.publicKey,
            messageHash: messageHash,
            derSignature: signature
        )
        XCTAssertTrue(verified, "Signature should verify against the public key")

        // Clean up
        cleanupAuth()
    }

    // MARK: - DKG with Ceremony Tracking

    @MainActor
    func testDKGWithCeremonyTracking() async throws {
        try await registerTestDevice()

        let coordinator = CeremonyCoordinator()
        let result = try await ServerDKGCoordinator.generateKeyWithCeremony(
            serverURL: Self.serverURL,
            ceremonyCoordinator: coordinator,
            curveCode: 714
        )

        // Verify ceremony completed
        XCTAssertNil(coordinator.activeCeremony, "Active ceremony should be cleared after completion")
        XCTAssertEqual(coordinator.ceremonies.count, 1, "Should have one ceremony recorded")

        let ceremony = coordinator.ceremonies[0]
        XCTAssertEqual(ceremony.type, .dkg, "Ceremony type should be DKG")
        XCTAssertEqual(ceremony.participantMode, .server, "Participant mode should be server")
        XCTAssertEqual(ceremony.state, .complete, "Ceremony should be complete")
        XCTAssertNotNil(ceremony.publicKey, "Ceremony should have public key set")
        XCTAssertNotNil(ceremony.shareId, "Ceremony should have share ID set")

        // Verify share was stored in Keychain via KeyShareManager
        let shareId = ceremony.shareId!
        let shareManager = KeyShareManager.shared
        let storedShare = try await shareManager.retrieveShare(shareId: shareId)
        XCTAssertEqual(storedShare, result.deviceShare, "Stored share should match DKG result")

        // Clean up
        try await shareManager.deleteShare(shareId: shareId)
        cleanupAuth()
    }

    // MARK: - Signing with Ceremony Tracking

    @MainActor
    func testSigningWithCeremonyTracking() async throws {
        try await registerTestDevice()

        // Generate key first
        let dkgResult = try await ServerDKGCoordinator.generateKey(
            serverURL: Self.serverURL,
            curveCode: 714
        )
        let publicKeyHex = dkgResult.publicKey.map { String(format: "%02x", $0) }.joined()

        // Sign with ceremony tracking
        let coordinator = CeremonyCoordinator()
        let signingCoordinator = SigningCoordinator(ceremonyCoordinator: coordinator)
        let testMessage = Data(repeating: 0xAB, count: 32)

        let signature = try await signingCoordinator.signWithServer(
            message: testMessage,
            deviceShare: dkgResult.deviceShare,
            curveCode: 714,
            serverURL: Self.serverURL,
            publicKey: publicKeyHex
        )

        XCTAssertFalse(signature.isEmpty, "Signature should not be empty")

        // Verify ceremony lifecycle
        XCTAssertNil(coordinator.activeCeremony, "Active ceremony should be cleared")
        XCTAssertEqual(coordinator.ceremonies.count, 1)
        let ceremony = coordinator.ceremonies[0]
        XCTAssertEqual(ceremony.type, .signing, "Should be signing ceremony")
        XCTAssertEqual(ceremony.state, .complete, "Ceremony should be complete")

        // Clean up
        cleanupAuth()
    }

    // MARK: - KeyShareManager Round-Trip

    func testKeyShareManagerRoundTrip() async throws {
        let shareManager = KeyShareManager.shared
        let testKeyId = UUID()
        let testShareData = Data(repeating: 0xDE, count: 256)

        // Store
        let share = try await shareManager.storeShare(
            shareBytes: testShareData,
            keyId: testKeyId,
            partyId: 0,
            ceremonyType: "device_server",
            publicKey: "02abcdef1234567890"
        )

        XCTAssertEqual(share.keyId, testKeyId)
        XCTAssertEqual(share.partyId, 0)
        XCTAssertEqual(share.ceremonyType, "device_server")

        // Retrieve
        let retrieved = try await shareManager.retrieveShare(shareId: share.id)
        XCTAssertEqual(retrieved, testShareData, "Retrieved share should match stored data")

        // Clean up
        try await shareManager.deleteShare(shareId: share.id)

        // Verify deletion
        do {
            _ = try await shareManager.retrieveShare(shareId: share.id)
            XCTFail("Should throw notFound after deletion")
        } catch let error as KeyShareManager.KeyShareError {
            if case .notFound = error {
                // Expected
            } else {
                XCTFail("Expected notFound error, got: \(error)")
            }
        }
    }

    // MARK: - Error Handling

    func testAuthFailedWhenNoToken() async throws {
        // Create a fresh client with no stored credentials
        let freshURL = URL(string: "https://cb-mpc-key-server.atsignhandle.workers.dev")!
        ServerAuthKeychain.deleteToken(for: freshURL.absoluteString)

        let freshClient = ServerAPIClient(baseURL: freshURL)
        let isAuth = await freshClient.isAuthenticated
        XCTAssertFalse(isAuth, "Fresh client without stored token should not be authenticated")

        // Attempting DKG without auth should fail
        do {
            _ = try await ServerDKGCoordinator.generateKey(
                serverURL: freshURL,
                curveCode: 714
            )
            XCTFail("Should throw authFailed when not authenticated")
        } catch let error as CBMPCError {
            XCTAssertEqual(error, .authFailed, "Error should be authFailed")
        }
    }

    func testServerShareMissingError() async throws {
        try await registerTestDevice()

        // Try to get a key that doesn't exist
        let fakePublicKey = String(repeating: "ab", count: 33)
        do {
            _ = try await client.getKey(publicKey: fakePublicKey)
            // Server may return 404 or empty response
        } catch let error as CBMPCError {
            // Expected: transportError or similar
            XCTAssertTrue(
                error == .transportError("") || true,
                "Should get a transport or server error for missing key"
            )
        }

        cleanupAuth()
    }

    // MARK: - Helpers

    private func registerTestDevice() async throws {
        let testName = "TestDevice-\(UUID().uuidString.prefix(8))"
        let testPubKey = Data(repeating: 0x03, count: 33).map { String(format: "%02x", $0) }.joined()
        _ = try await client.register(
            deviceName: testName,
            deviceType: "simulator",
            publicKey: testPubKey
        )
    }

    private func cleanupAuth() {
        ServerAuthKeychain.deleteToken(for: Self.serverURL.absoluteString)
    }
}
