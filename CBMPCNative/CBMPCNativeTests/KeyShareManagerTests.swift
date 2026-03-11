import XCTest
@testable import CBMPCNative

class KeyShareManagerTests: XCTestCase {
    let manager = KeyShareManager.shared
    var testKeyId: UUID!

    override func setUp() {
        super.setUp()
        testKeyId = UUID()
    }

    override func tearDown() async throws {
        try? await manager.deleteShare(shareId: "cb-mpc.share.\(testKeyId!.uuidString).0")
        try? await manager.deleteShare(shareId: "cb-mpc.share.\(testKeyId!.uuidString).1")
    }

    func testStoreAndRetrieveShare() async throws {
        let testData = Data([0, 1, 2, 3, 4, 5, 6, 7])
        let share = try await manager.storeShare(
            shareBytes: testData,
            keyId: testKeyId,
            partyId: 0,
            ceremonyType: "device_device",
            publicKey: "02abcd"
        )

        XCTAssertEqual(share.partyId, 0)
        XCTAssertEqual(share.ceremonyType, "device_device")
        XCTAssertEqual(share.publicKey, "02abcd")
        XCTAssertTrue(share.id.contains(testKeyId.uuidString))

        let retrieved = try await manager.retrieveShare(shareId: share.id)
        XCTAssertEqual(retrieved, testData)
    }

    func testRetrieveNonExistent() async {
        do {
            _ = try await manager.retrieveShare(shareId: "nonexistent-key-id")
            XCTFail("Should throw notFound")
        } catch KeyShareManager.KeyShareError.notFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStoreOverwrite() async throws {
        let data1 = Data([1, 2, 3])
        let data2 = Data([4, 5, 6])

        let share1 = try await manager.storeShare(
            shareBytes: data1, keyId: testKeyId, partyId: 0, ceremonyType: "device_device"
        )

        let share2 = try await manager.storeShare(
            shareBytes: data2, keyId: testKeyId, partyId: 0, ceremonyType: "device_device"
        )

        XCTAssertEqual(share1.id, share2.id) // Same ID
        let retrieved = try await manager.retrieveShare(shareId: share2.id)
        XCTAssertEqual(retrieved, data2) // New data
    }

    func testDeleteShare() async throws {
        let testData = Data([9, 8, 7])
        let share = try await manager.storeShare(
            shareBytes: testData, keyId: testKeyId, partyId: 0, ceremonyType: "device_server"
        )

        try await manager.deleteShare(shareId: share.id)

        do {
            _ = try await manager.retrieveShare(shareId: share.id)
            XCTFail("Should throw notFound after deletion")
        } catch KeyShareManager.KeyShareError.notFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeleteNonExistent() async throws {
        // Should not throw
        try await manager.deleteShare(shareId: "does-not-exist")
    }

    func testStoreMultipleParties() async throws {
        let data0 = Data([1, 1, 1])
        let data1 = Data([2, 2, 2])

        let share0 = try await manager.storeShare(
            shareBytes: data0, keyId: testKeyId, partyId: 0, ceremonyType: "device_device"
        )
        let share1 = try await manager.storeShare(
            shareBytes: data1, keyId: testKeyId, partyId: 1, ceremonyType: "device_device"
        )

        XCTAssertNotEqual(share0.id, share1.id)

        let r0 = try await manager.retrieveShare(shareId: share0.id)
        let r1 = try await manager.retrieveShare(shareId: share1.id)
        XCTAssertEqual(r0, data0)
        XCTAssertEqual(r1, data1)
    }

    func testStoreLargeShare() async throws {
        let largeData = Data(repeating: 0xBB, count: 4096)
        let share = try await manager.storeShare(
            shareBytes: largeData, keyId: testKeyId, partyId: 0, ceremonyType: "device_server"
        )
        let retrieved = try await manager.retrieveShare(shareId: share.id)
        XCTAssertEqual(retrieved, largeData)
    }

    func testListSharesEmpty() async throws {
        let shares = try await manager.listShares(for: UUID())
        XCTAssertTrue(shares.isEmpty)
    }
}
