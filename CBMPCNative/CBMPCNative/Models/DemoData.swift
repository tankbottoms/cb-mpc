import Foundation

struct DemoDataGenerator {

    /// Generate real cryptographic demo keys using 2-party ECDSA DKG.
    /// Returns (keys, keyDataMap) where keyDataMap maps UUID -> serialized key data.
    static func generateRealDemoKeys() throws -> ([ManagedKey], [UUID: Data]) {
        let engine = CBMPCCryptoEngine()
        let curveCode = 714
        var keys: [ManagedKey] = []
        var keyDataMap: [UUID: Data] = [:]

        let specs: [(String, KeyType, String?)] = [
            ("Example Wallet", .simple, nil),
            ("Master Key", .hdMaster, "m"),
            ("Derived Account 0", .hdChild, "m/44'/60'/0'/0/0"),
        ]

        for (name, type, path) in specs {
            let (pubKey, serialized) = try engine.generateKey(curveCode: curveCode)
            let id = UUID()
            let pubHex = pubKey.map { String(format: "%02x", $0) }.joined()

            let key = ManagedKey(
                id: id,
                name: name,
                publicKey: pubHex,
                keyType: type,
                curveCode: Int32(curveCode),
                derivationPath: path,
                parentKeyId: nil,
                storageLocation: .secureEnclave,
                createdAt: Date(),
                lastUsedAt: nil,
                isBackedUp: false,
                signingRecords: []
            )
            keys.append(key)
            keyDataMap[id] = serialized
        }

        return (keys, keyDataMap)
    }
}
