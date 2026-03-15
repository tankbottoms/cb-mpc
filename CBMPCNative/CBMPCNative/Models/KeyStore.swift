import Foundation
import CoreData
import SwiftUI
import CryptoKit

@MainActor
class KeyStore: NSObject, ObservableObject {
    @Published var keys: [ManagedKey] = []
    @Published var selectedKeyId: UUID?
    @Published var recentlyAddedKeyId: UUID?

    let persistenceController: PersistenceController
    private let cryptoEngine = CBMPCCryptoEngine()

    init(persistenceController: PersistenceController = PersistenceController.shared) {
        self.persistenceController = persistenceController
        super.init()
        loadKeys()
    }

    func loadKeys() {
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ManagedKeyEntity")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "createdAt", ascending: false)]
        fetchRequest.relationshipKeyPathsForPrefetching = ["signingRecords"]

        do {
            let results = try context.fetch(fetchRequest)
            self.keys = results.map { entity in
                var key = managedKeyToModel(entity)
                // Load signing records from CoreData relationship
                if let recordSet = entity.value(forKey: "signingRecords") as? Set<NSManagedObject> {
                    key.signingRecords = recordSet.map { signingRecordToModel($0) }
                        .sorted { $0.timestamp > $1.timestamp }
                }
                return key
            }
        } catch {
            print("Error fetching keys: \(error)")
            self.keys = []
        }
    }

    func addKey(_ key: ManagedKey) {
        let context = persistenceController.container.viewContext
        saveKeyToEntity(key, in: context)
        persistenceController.save()
        loadKeys()
        recentlyAddedKeyId = key.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.recentlyAddedKeyId == key.id {
                self?.recentlyAddedKeyId = nil
            }
        }
    }

    func updateKeyName(_ keyId: UUID, newName: String) {
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ManagedKeyEntity")
        fetchRequest.predicate = NSPredicate(format: "id == %@", keyId as CVarArg)

        do {
            if let entity = try context.fetch(fetchRequest).first {
                entity.setValue(newName, forKey: "name")
                persistenceController.save()
                loadKeys()
            }
        } catch {
            print("Error updating key name: \(error)")
        }
    }

    func deleteKey(_ keyId: UUID) {
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ManagedKeyEntity")
        fetchRequest.predicate = NSPredicate(format: "id == %@", keyId as CVarArg)

        do {
            let results = try context.fetch(fetchRequest)
            for result in results {
                context.delete(result)
            }
            // Also remove key data from UserDefaults
            UserDefaults.standard.removeObject(forKey: "key_\(keyId.uuidString)")
            persistenceController.save()
            loadKeys()
        } catch {
            print("Error deleting key: \(error)")
        }
    }

    /// Reorder keys by moving from source indices to destination
    func moveKeys(from source: IndexSet, to destination: Int) {
        keys.move(fromOffsets: source, toOffset: destination)

        // Update sortOrder for all keys and persist
        let context = persistenceController.container.viewContext
        for (index, key) in keys.enumerated() {
            keys[index].sortOrder = Int32(index)

            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ManagedKeyEntity")
            fetchRequest.predicate = NSPredicate(format: "id == %@", key.id as CVarArg)
            if let entity = try? context.fetch(fetchRequest).first {
                entity.setValue(Int32(index), forKey: "sortOrder")
            }
        }
        persistenceController.save()
    }

    @Published var isSeedingDemoData = false

    func seedDemoData() {
        guard !isSeedingDemoData else { return }
        isSeedingDemoData = true

        let context = persistenceController.container.viewContext

        // Clear existing data
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ManagedKeyEntity")
        do {
            let results = try context.fetch(fetchRequest)
            for result in results {
                context.delete(result)
            }
            try context.save()
        } catch {
            print("Failed to clear data: \(error)")
            isSeedingDemoData = false
            return
        }

        // Clear old key data from UserDefaults
        for key in keys {
            UserDefaults.standard.removeObject(forKey: "key_\(key.id.uuidString)")
        }
        keys = []

        // Generate real cryptographic keys on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let (demoKeys, keyDataMap) = try DemoDataGenerator.generateRealDemoKeys()

                DispatchQueue.main.async {
                    guard let self = self else { return }
                    for key in demoKeys {
                        if let keyData = keyDataMap[key.id] {
                            UserDefaults.standard.set(keyData, forKey: "key_\(key.id.uuidString)")
                        }
                        self.saveKeyToEntity(key, in: context)
                    }
                    self.persistenceController.save()
                    self.loadKeys()
                    self.isSeedingDemoData = false
                }
            } catch {
                DispatchQueue.main.async {
                    print("Failed to generate demo keys: \(error)")
                    self?.isSeedingDemoData = false
                }
            }
        }
    }

    private func saveKeyToEntity(_ key: ManagedKey, in context: NSManagedObjectContext) {
        let entity = NSEntityDescription.insertNewObject(forEntityName: "ManagedKeyEntity", into: context)
        entity.setValue(key.id, forKey: "id")
        entity.setValue(key.name, forKey: "name")
        entity.setValue(key.publicKey, forKey: "publicKey")
        entity.setValue(key.keyType.rawValue, forKey: "keyType")
        entity.setValue(key.curveCode, forKey: "curveCode")
        entity.setValue(key.derivationPath, forKey: "derivationPath")
        entity.setValue(key.parentKeyId, forKey: "parentKeyId")
        entity.setValue(key.storageLocation.rawValue, forKey: "storageLocation")
        entity.setValue(key.createdAt, forKey: "createdAt")
        entity.setValue(key.lastUsedAt, forKey: "lastUsedAt")
        entity.setValue(key.isBackedUp, forKey: "isBackedUp")
        entity.setValue(key.sortOrder, forKey: "sortOrder")
    }

    private func managedKeyToModel(_ entity: NSManagedObject) -> ManagedKey {
        let id = entity.value(forKey: "id") as? UUID ?? UUID()
        let name = entity.value(forKey: "name") as? String ?? "Unknown"
        let publicKey = entity.value(forKey: "publicKey") as? String ?? ""
        let keyTypeRaw = entity.value(forKey: "keyType") as? String ?? KeyType.simple.rawValue
        let keyType = KeyType(rawValue: keyTypeRaw) ?? .simple
        let curveCode = entity.value(forKey: "curveCode") as? Int ?? 714
        let derivationPath = entity.value(forKey: "derivationPath") as? String
        let parentKeyId = entity.value(forKey: "parentKeyId") as? UUID
        let storageLocationRaw = entity.value(forKey: "storageLocation") as? String ?? StorageLocation.secureEnclave.rawValue
        let storageLocation = StorageLocation(rawValue: storageLocationRaw) ?? .secureEnclave
        let createdAt = entity.value(forKey: "createdAt") as? Date ?? Date()
        let lastUsedAt = entity.value(forKey: "lastUsedAt") as? Date
        let isBackedUp = entity.value(forKey: "isBackedUp") as? Bool ?? false
        let sortOrder = entity.value(forKey: "sortOrder") as? Int32 ?? 0

        return ManagedKey(
            id: id,
            name: name,
            publicKey: publicKey,
            keyType: keyType,
            curveCode: Int32(curveCode),
            derivationPath: derivationPath,
            parentKeyId: parentKeyId,
            storageLocation: storageLocation,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            isBackedUp: isBackedUp,
            sortOrder: sortOrder,
            signingRecords: []
        )
    }

    private func signingRecordToModel(_ entity: NSManagedObject) -> SigningRecord {
        return SigningRecord(
            id: entity.value(forKey: "id") as? UUID ?? UUID(),
            messageHash: entity.value(forKey: "messageHash") as? String ?? "",
            signature: entity.value(forKey: "signature") as? String ?? "",
            timestamp: entity.value(forKey: "timestamp") as? Date ?? Date(),
            verified: entity.value(forKey: "verified") as? Bool ?? false
        )
    }

    /// Add a signing record to a key's history and persist to CoreData
    func addSigningRecord(_ record: SigningRecord, to keyId: UUID) {
        // Set keyId on record
        var recordWithKey = record
        recordWithKey.keyId = keyId

        // Update in-memory
        if let idx = keys.firstIndex(where: { $0.id == keyId }) {
            keys[idx].signingRecords.insert(recordWithKey, at: 0)
        }

        // Persist to CoreData
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ManagedKeyEntity")
        fetchRequest.predicate = NSPredicate(format: "id == %@", keyId as CVarArg)

        do {
            guard let keyEntity = try context.fetch(fetchRequest).first else { return }

            let recordEntity = NSEntityDescription.insertNewObject(forEntityName: "SigningRecordEntity", into: context)
            recordEntity.setValue(record.id, forKey: "id")
            recordEntity.setValue(record.messageHash, forKey: "messageHash")
            recordEntity.setValue(record.signature, forKey: "signature")
            recordEntity.setValue(record.timestamp, forKey: "timestamp")
            recordEntity.setValue(record.verified, forKey: "verified")
            recordEntity.setValue(record.transportInfo, forKey: "transportInfo")
            recordEntity.setValue(keyEntity, forKey: "managedKey")

            // Update lastUsedAt on the key
            keyEntity.setValue(Date(), forKey: "lastUsedAt")

            persistenceController.save()
        } catch {
            print("Error saving signing record: \(error)")
        }
    }

    /// Delete a signing record from a key's history
    func deleteSigningRecord(_ recordId: UUID, from keyId: UUID) {
        // Update in-memory
        if let idx = keys.firstIndex(where: { $0.id == keyId }) {
            keys[idx].signingRecords.removeAll { $0.id == recordId }
        }

        // Delete from CoreData
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "SigningRecordEntity")
        fetchRequest.predicate = NSPredicate(format: "id == %@", recordId as CVarArg)

        do {
            let results = try context.fetch(fetchRequest)
            for result in results {
                context.delete(result)
            }
            persistenceController.save()
        } catch {
            print("Error deleting signing record: \(error)")
        }
    }

    /// Clear all signing records from CoreData and in-memory
    func clearAllSigningRecords() {
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "SigningRecordEntity")

        do {
            let results = try context.fetch(fetchRequest)
            for result in results {
                context.delete(result)
            }
            persistenceController.save()

            // Clear in-memory
            for idx in keys.indices {
                keys[idx].signingRecords = []
            }
        } catch {
            print("Error clearing all signing records: \(error)")
        }
    }

    /// Derive a child key from an HD master key using actual BIP-32 HD derivation
    func deriveChildKey(from masterKey: ManagedKey, path: String, name: String) throws -> ManagedKey {
        let curveCode = Int(masterKey.curveCode)
        let parentOrigin = TransportOrigin.load(for: masterKey.id)

        guard let masterKeyData = UserDefaults.standard.data(forKey: "key_\(masterKey.id.uuidString)") else {
            throw CBMPCError.invalidKeyData
        }

        // Parse BIP-44 path string (e.g., "m/44'/60'/0'/0/0") into UInt32 array
        let pathIndices = Self.parseBIP44Path(path)

        let publicKey: Data
        let serializedKey: Data

        if parentOrigin == .local || isPackedKeyData(for: masterKey.id) {
            // Both HD master shares on device — derive locally
            let result = try cryptoEngine.deriveChildFromHD(
                masterKeyData: masterKeyData,
                path: pathIndices,
                curveCode: curveCode
            )
            publicKey = result.publicKey
            serializedKey = result.serializedKey
        } else {
            // Fallback: generate independent key (parent is server/peer-backed with single share)
            print("[KeyStore] WARNING: HD master has single share — generating independent child key")
            let result = try cryptoEngine.generateKey(curveCode: curveCode)
            publicKey = result.publicKey
            serializedKey = result.serializedKey
        }

        let publicKeyHex = publicKey.map { String(format: "%02x", $0) }.joined()

        let childKey = ManagedKey(
            id: UUID(),
            name: name,
            publicKey: publicKeyHex,
            keyType: .hdChild,
            curveCode: Int32(curveCode),
            derivationPath: path,
            parentKeyId: masterKey.id,
            storageLocation: .secureEnclave,
            createdAt: Date(),
            lastUsedAt: nil,
            isBackedUp: false,
            signingRecords: []
        )

        UserDefaults.standard.set(serializedKey, forKey: "key_\(childKey.id.uuidString)")

        // Propagate transport origin from parent to child (for display badge)
        TransportOrigin.save(parentOrigin, for: childKey.id)
        if let parentCoSigner = TransportOrigin.coSignerRef(for: masterKey.id) {
            TransportOrigin.saveCoSigner(parentCoSigner, for: childKey.id)
        }
        // Propagate server URL if parent is server-backed
        if let serverURL = UserDefaults.standard.string(forKey: "key_\(masterKey.id.uuidString)_server") {
            UserDefaults.standard.set(serverURL, forKey: "key_\(childKey.id.uuidString)_server")
        }
        // Mark as locally-derived (both shares on device even though badge shows server/peer)
        UserDefaults.standard.set(true, forKey: "key_\(childKey.id.uuidString)_localDerived")

        print("[KeyStore] Derived HD-child '\(name)' via HD derivation from parent \(masterKey.name), origin=\(parentOrigin.rawValue)")

        addKey(childKey)
        return childKey
    }

    /// Derive a child key from a server-backed HD master key (async — downloads server share)
    func deriveChildKeyAsync(from masterKey: ManagedKey, path: String, name: String) async throws -> ManagedKey {
        let curveCode = Int(masterKey.curveCode)

        guard let masterKeyData = UserDefaults.standard.data(forKey: "key_\(masterKey.id.uuidString)") else {
            throw CBMPCError.invalidKeyData
        }
        guard let serverURLString = UserDefaults.standard.string(forKey: "key_\(masterKey.id.uuidString)_server"),
              let serverURL = URL(string: serverURLString) else {
            throw CBMPCError.serverUnreachable
        }

        let pathIndices = Self.parseBIP44Path(path)

        print("[KeyStore] Deriving child from server-backed HD master via HD derivation...")
        let (childPubKey, deviceChildShare, _) = try await cryptoEngine.deriveChildFromHDRemote(
            deviceHDShare: masterKeyData,
            path: pathIndices,
            curveCode: curveCode,
            serverURL: serverURL,
            masterPublicKey: masterKey.publicKey
        )

        let publicKeyHex = childPubKey.map { String(format: "%02x", $0) }.joined()

        let childKey = ManagedKey(
            id: UUID(),
            name: name,
            publicKey: publicKeyHex,
            keyType: .hdChild,
            curveCode: Int32(curveCode),
            derivationPath: path,
            parentKeyId: masterKey.id,
            storageLocation: .secureEnclave,
            createdAt: Date(),
            lastUsedAt: nil,
            isBackedUp: false,
            signingRecords: []
        )

        // Store only device child share (server child share was uploaded by ServerDKGCoordinator)
        UserDefaults.standard.set(deviceChildShare, forKey: "key_\(childKey.id.uuidString)")
        TransportOrigin.save(.server, for: childKey.id)
        TransportOrigin.saveCoSigner(serverURL.absoluteString, for: childKey.id)
        UserDefaults.standard.set(serverURL.absoluteString, forKey: "key_\(childKey.id.uuidString)_server")

        print("[KeyStore] Derived server-backed HD-child '\(name)' — child share stored, server share uploaded")

        addKey(childKey)
        return childKey
    }

    /// Parse a BIP-44 path string into UInt32 indices
    /// e.g., "m/44'/60'/0'/0/0" → [0x8000002C, 0x8000003C, 0x80000000, 0, 0]
    private static func parseBIP44Path(_ path: String) -> [UInt32] {
        let components = path.split(separator: "/")
        return components.compactMap { component in
            let str = String(component)
            if str == "m" { return nil }
            let hardened = str.hasSuffix("'")
            let clean = str.replacingOccurrences(of: "'", with: "")
            guard let index = UInt32(clean) else { return nil }
            return hardened ? (index | 0x80000000) : index
        }
    }

    // MARK: - iCloud Backup

    func backupToICloud() {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.xyz.atsignhandle.cb-mpc") else {
            print("iCloud not available")
            return
        }

        let backupDir = containerURL.appendingPathComponent("Documents/Key-MGMT-CB-MPC", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create iCloud backup directory: \(error)")
            return
        }

        for key in keys {
            var dict: [String: Any] = [
                "id": key.id.uuidString,
                "name": key.name,
                "publicKey": key.publicKey,
                "keyType": key.keyType.rawValue,
                "curveCode": Int(key.curveCode),
                "createdAt": ISO8601DateFormatter().string(from: key.createdAt),
                "storageLocation": key.storageLocation.rawValue
            ]
            if let path = key.derivationPath {
                dict["derivationPath"] = path
            }
            if let parentId = key.parentKeyId {
                dict["parentKeyId"] = parentId.uuidString
            }
            if let keyData = UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") {
                dict["keyData"] = keyData.base64EncodedString()
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                let addr = key.shortAddress.replacingOccurrences(of: "0x", with: "")
                let fileName = "\(addr)-\(key.keyType.rawValue).json"
                let fileURL = backupDir.appendingPathComponent(fileName)
                try? jsonData.write(to: fileURL)
            }
        }
    }

    // MARK: - Cryptographic Operations

    /// Generate a real cryptographic key using DKG (local, both shares on device)
    /// Uses HD DKG (cbmpc_hd_ecdsa2p_dkg) for hdMaster keys, standard DKG for simple keys
    func generateCryptographicKey(name: String, keyType: KeyType) throws -> ManagedKey {
        let curveCode = 714 // secp256k1

        do {
            let publicKey: Data
            let serializedKey: Data

            if keyType == .hdMaster {
                let result = try cryptoEngine.generateHDKey(curveCode: curveCode)
                publicKey = result.publicKey
                serializedKey = result.serializedKey
            } else {
                let result = try cryptoEngine.generateKey(curveCode: curveCode)
                publicKey = result.publicKey
                serializedKey = result.serializedKey
            }

            let publicKeyHex = publicKey.map { String(format: "%02x", $0) }.joined()
            let derivationPath: String? = (keyType == .hdMaster) ? "m" : nil

            let managedKey = ManagedKey(
                id: UUID(),
                name: name,
                publicKey: publicKeyHex,
                keyType: keyType,
                curveCode: Int32(curveCode),
                derivationPath: derivationPath,
                parentKeyId: nil,
                storageLocation: .secureEnclave,
                createdAt: Date(),
                lastUsedAt: nil,
                isBackedUp: false,
                signingRecords: []
            )

            UserDefaults.standard.set(serializedKey, forKey: "key_\(managedKey.id.uuidString)")
            TransportOrigin.save(.local, for: managedKey.id)

            addKey(managedKey)
            return managedKey
        } catch {
            print("Key generation error for \(keyType): \(error)")
            throw error
        }
    }

    /// Generate a server-backed key (device share local, server share remote)
    /// Uses HD DKG (cbmpc_hd_ecdsa2p_dkg) for hdMaster keys, standard DKG for simple keys
    func generateServerKey(name: String, keyType: KeyType, serverURL: URL) async throws -> ManagedKey {
        let curveCode = 714
        let startTime = Date()

        print("[KeyStore] generateServerKey: START — name='\(name)', type=\(keyType.rawValue), server=\(serverURL.absoluteString)")

        let publicKey: Data
        let deviceShare: Data

        if keyType == .hdMaster {
            let result = try await cryptoEngine.generateHDKeyRemote(serverURL: serverURL, curveCode: curveCode)
            publicKey = result.publicKey
            deviceShare = result.deviceShare
        } else {
            let result = try await cryptoEngine.generateKeyRemote(serverURL: serverURL, curveCode: curveCode)
            publicKey = result.publicKey
            deviceShare = result.deviceShare
        }

        let publicKeyHex = publicKey.map { String(format: "%02x", $0) }.joined()
        let duration = Date().timeIntervalSince(startTime)

        print("[KeyStore] generateServerKey: DKG complete in \(String(format: "%.2f", duration))s — pubKey=\(String(publicKeyHex.prefix(16)))..., deviceShare=\(deviceShare.count) bytes")

        let derivationPath: String? = (keyType == .hdMaster) ? "m" : nil

        let managedKey = ManagedKey(
            id: UUID(),
            name: name,
            publicKey: publicKeyHex,
            keyType: keyType,
            curveCode: Int32(curveCode),
            derivationPath: derivationPath,
            parentKeyId: nil,
            storageLocation: .secureEnclave,
            createdAt: Date(),
            lastUsedAt: nil,
            isBackedUp: false,
            signingRecords: []
        )

        // Store only the device share (not the full two-share pack)
        UserDefaults.standard.set(deviceShare, forKey: "key_\(managedKey.id.uuidString)")
        TransportOrigin.save(.server, for: managedKey.id)
        TransportOrigin.saveCoSigner(serverURL.absoluteString, for: managedKey.id)

        // Store server URL for this key
        UserDefaults.standard.set(serverURL.absoluteString, forKey: "key_\(managedKey.id.uuidString)_server")

        print("[KeyStore] generateServerKey: DONE — key stored with server origin, serverURL saved")

        addKey(managedKey)
        return managedKey
    }

    /// Check if stored key data is a packed 2-share key (both shares on device)
    /// Packed format: [4-byte k0 length LE][k0 bytes][k1 bytes]
    private func isPackedKeyData(for keyId: UUID) -> Bool {
        // Explicit flag from deriveChildKey
        if UserDefaults.standard.bool(forKey: "key_\(keyId.uuidString)_localDerived") {
            return true
        }
        guard let data = UserDefaults.standard.data(forKey: "key_\(keyId.uuidString)"),
              data.count > 4 else { return false }
        let k0Size = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        let k0End = 4 + Int(k0Size)
        // k0 must be non-empty, k1 must be non-empty, total must match
        return k0Size > 0 && k0End < data.count
    }

    /// Sign a message with a stored key, routing based on transport origin
    func signMessage(_ message: String, with key: ManagedKey) throws -> String {
        guard let keyData = UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") else {
            throw CBMPCError.invalidKeyData
        }

        let origin = TransportOrigin.load(for: key.id)

        // SHA-256 pre-hash: C-level MPC sign expects a 32-byte hash
        let messageData = message.data(using: .utf8) ?? Data()
        let messageHash = SHA256.hash(data: messageData)
        let hashData = Data(messageHash)

        switch origin {
        case .local:
            // Both shares on device — existing path
            let signatureData = try cryptoEngine.signMessage(hashData, keyData: keyData, curveCode: Int(key.curveCode))
            return CBMPCCryptoEngine.formatSignature(signatureData)

        case .server, .peer:
            // Check if both shares are on device (e.g., HD-child derived from server/peer parent)
            if isPackedKeyData(for: key.id) {
                print("[KeyStore] signMessage: key \(key.name) has \(origin.rawValue) origin but both shares on device — signing locally")
                let signatureData = try cryptoEngine.signMessage(hashData, keyData: keyData, curveCode: Int(key.curveCode))
                return CBMPCCryptoEngine.formatSignature(signatureData)
            }
            // Single share only — need async path
            throw CBMPCError.transportError("Use signMessageAsync for \(origin.rawValue)-backed keys")
        }
    }

    /// Async sign for server-backed and peer-backed keys
    func signMessageAsync(_ message: String, with key: ManagedKey) async throws -> String {
        guard let keyData = UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") else {
            throw CBMPCError.invalidKeyData
        }

        let origin = TransportOrigin.load(for: key.id)

        // SHA-256 pre-hash: C-level MPC sign expects a 32-byte hash
        let messageData = message.data(using: .utf8) ?? Data()
        let messageHash = SHA256.hash(data: messageData)
        let hashData = Data(messageHash)

        switch origin {
        case .local:
            // Local keys can use sync path
            let signatureData = try cryptoEngine.signMessage(hashData, keyData: keyData, curveCode: Int(key.curveCode))
            return CBMPCCryptoEngine.formatSignature(signatureData)

        case .server:
            // Check if both shares are on device (HD-child derived from server parent)
            if isPackedKeyData(for: key.id) {
                print("[KeyStore] signMessageAsync: key \(key.name) is locally-derived from server parent — signing with local shares")
                let signatureData = try cryptoEngine.signMessage(hashData, keyData: keyData, curveCode: Int(key.curveCode))
                return CBMPCCryptoEngine.formatSignature(signatureData)
            }
            // Single share — need server
            guard let serverURLString = UserDefaults.standard.string(forKey: "key_\(key.id.uuidString)_server"),
                  let serverURL = URL(string: serverURLString) else {
                throw CBMPCError.serverUnreachable
            }
            print("[KeyStore] signMessageAsync: key \(key.name) — downloading server share from \(serverURL.host ?? "?")")
            let signatureData = try await cryptoEngine.signMessageRemote(
                hashData,
                deviceShare: keyData,
                curveCode: Int(key.curveCode),
                serverURL: serverURL,
                publicKey: key.publicKey
            )
            return CBMPCCryptoEngine.formatSignature(signatureData)

        case .peer:
            // Check if both shares are on device (HD-child derived from peer parent)
            if isPackedKeyData(for: key.id) {
                print("[KeyStore] signMessageAsync: key \(key.name) is locally-derived from peer parent — signing with local shares")
                let signatureData = try cryptoEngine.signMessage(hashData, keyData: keyData, curveCode: Int(key.curveCode))
                return CBMPCCryptoEngine.formatSignature(signatureData)
            }
            throw CBMPCError.transportError("Peer signing requires both devices online")
        }
    }
}
