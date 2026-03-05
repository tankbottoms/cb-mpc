import Foundation

struct DemoDataGenerator {
    static func generateDemoKeys() -> [ManagedKey] {
        let now = Date()
        let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now
        let twoHoursAgo = Calendar.current.date(byAdding: .hour, value: -2, to: now) ?? now

        // Simple key
        let simpleKey = ManagedKey(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789012") ?? UUID(),
            name: "Example Wallet",
            publicKey: "02a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6",
            keyType: .simple,
            curveCode: 714,
            derivationPath: nil,
            parentKeyId: nil,
            storageLocation: .secureEnclave,
            createdAt: twoHoursAgo,
            lastUsedAt: oneHourAgo,
            isBackedUp: true,
            signingRecords: [
                SigningRecord(
                    id: UUID(),
                    messageHash: "abc123def456ghi789jkl012mno345pqr678stu901vwx234yz",
                    signature: "3045022100abc123def456ghi789jkl012mno345pqr678stu901vwx234yz0220def456ghi789jkl012mno345pqr678stu901vwx234yz",
                    timestamp: oneHourAgo,
                    verified: true
                )
            ]
        )

        // HD Master key
        let hdMasterKey = ManagedKey(
            id: UUID(uuidString: "87654321-4321-4321-4321-210987654321") ?? UUID(),
            name: "Master Key",
            publicKey: "03x9y8z7w6v5u4t3s2r1q0p9o8n7m6l5k4j3i2h1g0f9e8d7c6b5a4",
            keyType: .hdMaster,
            curveCode: 714,
            derivationPath: nil,
            parentKeyId: nil,
            storageLocation: .secureEnclave,
            createdAt: twoHoursAgo,
            lastUsedAt: oneHourAgo,
            isBackedUp: true,
            signingRecords: []
        )

        // HD Child key
        let hdChildKey = ManagedKey(
            id: UUID(),
            name: "Derived Account 0",
            publicKey: "02aaabbbcccdddeeefffffgggghhhhiiiihjjjjkkkkllllmmmmnnnno",
            keyType: .hdChild,
            curveCode: 714,
            derivationPath: "m/44'/60'/0'/0/0",
            parentKeyId: UUID(uuidString: "87654321-4321-4321-4321-210987654321"),
            storageLocation: .keychain,
            createdAt: oneHourAgo,
            lastUsedAt: nil,
            isBackedUp: false,
            signingRecords: []
        )

        return [simpleKey, hdMasterKey, hdChildKey]
    }
}
