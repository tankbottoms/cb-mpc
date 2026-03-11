import XCTest
@testable import CBMPCNative

class CeremonyMessageTests: XCTestCase {
    func testCeremonyInitMessage() throws {
        let session = CeremonySession(type: .dkg, participantMode: .device, localPartyId: 0)
        let message = CeremonyMessage.ceremonyInit(session)
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)
        if case .ceremonyInit(let s) = decoded {
            XCTAssertEqual(s.id, session.id)
            XCTAssertEqual(s.type, .dkg)
        } else {
            XCTFail("Expected .ceremonyInit")
        }
    }

    func testDKGCommitmentsMessage() throws {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let message = CeremonyMessage.dkgCommitments(data)
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)
        if case .dkgCommitments(let d) = decoded {
            XCTAssertEqual(d, data)
        } else {
            XCTFail("Expected .dkgCommitments")
        }
    }

    func testDKGContributionMessage() throws {
        let data = Data(repeating: 0xAB, count: 64)
        let message = CeremonyMessage.dkgContribution(data)
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)
        if case .dkgContribution(let d) = decoded {
            XCTAssertEqual(d, data)
        } else {
            XCTFail("Expected .dkgContribution")
        }
    }

    func testSigningRequestMessage() throws {
        let hash = Data(repeating: 0x01, count: 32)
        let message = CeremonyMessage.signingRequest(hash)
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)
        if case .signingRequest(let d) = decoded {
            XCTAssertEqual(d, hash)
        } else {
            XCTFail("Expected .signingRequest")
        }
    }

    func testSigningResponseMessage() throws {
        let sig = Data(repeating: 0xFF, count: 70)
        let message = CeremonyMessage.signingResponse(sig)
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)
        if case .signingResponse(let d) = decoded {
            XCTAssertEqual(d, sig)
        } else {
            XCTFail("Expected .signingResponse")
        }
    }

    func testErrorMessage() throws {
        let message = CeremonyMessage.error("Connection lost")
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)
        if case .error(let msg) = decoded {
            XCTAssertEqual(msg, "Connection lost")
        } else {
            XCTFail("Expected .error")
        }
    }

    func testAllMessageTypesRoundTrip() throws {
        let session = CeremonySession(type: .signing, participantMode: .server, localPartyId: 1)
        let messages: [CeremonyMessage] = [
            .ceremonyInit(session),
            .dkgCommitments(Data([1, 2, 3])),
            .dkgContribution(Data([4, 5, 6])),
            .signingRequest(Data([7, 8, 9])),
            .signingResponse(Data([10, 11, 12])),
            .error("test"),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for message in messages {
            let encoded = try encoder.encode(message)
            let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)
            let reEncoded = try encoder.encode(decoded)
            // With sorted keys, double round-trip should produce identical JSON
            XCTAssertEqual(encoded, reEncoded, "Double round-trip failed")
        }
    }

    func testEmptyDataMessage() throws {
        let message = CeremonyMessage.dkgCommitments(Data())
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)
        if case .dkgCommitments(let d) = decoded {
            XCTAssertTrue(d.isEmpty)
        } else {
            XCTFail("Expected .dkgCommitments with empty data")
        }
    }

    func testLargeDataMessage() throws {
        let largeData = Data(repeating: 0xAA, count: 10_000)
        let message = CeremonyMessage.dkgContribution(largeData)
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CeremonyMessage.self, from: encoded)
        if case .dkgContribution(let d) = decoded {
            XCTAssertEqual(d.count, 10_000)
            XCTAssertEqual(d, largeData)
        } else {
            XCTFail("Expected .dkgContribution")
        }
    }
}
