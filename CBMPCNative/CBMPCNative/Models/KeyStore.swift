import Foundation
import CoreData
import SwiftUI

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

    /// Derive a child key from an HD master key
    func deriveChildKey(from masterKey: ManagedKey, path: String, name: String) throws -> ManagedKey {
        let curveCode = Int(masterKey.curveCode)

        let (publicKey, serializedKey) = try cryptoEngine.generateKey(curveCode: curveCode)
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
        addKey(childKey)
        return childKey
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
    func generateCryptographicKey(name: String, keyType: KeyType) throws -> ManagedKey {
        let curveCode = 714 // secp256k1

        do {
            let (publicKey, serializedKey) = try cryptoEngine.generateKey(curveCode: curveCode)
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
    func generateServerKey(name: String, keyType: KeyType, serverURL: URL) async throws -> ManagedKey {
        let curveCode = 714

        let (publicKey, deviceShare) = try await cryptoEngine.generateKeyRemote(serverURL: serverURL, curveCode: curveCode)
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

        // Store only the device share (not the full two-share pack)
        UserDefaults.standard.set(deviceShare, forKey: "key_\(managedKey.id.uuidString)")
        TransportOrigin.save(.server, for: managedKey.id)

        // Store server URL for this key
        UserDefaults.standard.set(serverURL.absoluteString, forKey: "key_\(managedKey.id.uuidString)_server")

        addKey(managedKey)
        return managedKey
    }

    /// Sign a message with a stored key, routing based on transport origin
    func signMessage(_ message: String, with key: ManagedKey) throws -> String {
        guard let keyData = UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") else {
            throw CBMPCError.invalidKeyData
        }

        let origin = TransportOrigin.load(for: key.id)

        switch origin {
        case .local:
            // Both shares on device — existing path
            let messageData = message.data(using: .utf8) ?? Data()
            let signatureData = try cryptoEngine.signMessage(messageData, keyData: keyData, curveCode: Int(key.curveCode))
            return CBMPCCryptoEngine.formatSignature(signatureData)

        case .server:
            // Server-backed key — need async path, throw for sync callers
            // Use signMessageAsync for server keys
            throw CBMPCError.transportError("Use signMessageAsync for server-backed keys")

        case .peer:
            // Peer key — both shares distributed, need peer transport
            throw CBMPCError.transportError("Use signMessageAsync for peer-backed keys")
        }
    }

    /// Async sign for server-backed and peer-backed keys
    func signMessageAsync(_ message: String, with key: ManagedKey) async throws -> String {
        guard let keyData = UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") else {
            throw CBMPCError.invalidKeyData
        }

        let origin = TransportOrigin.load(for: key.id)

        switch origin {
        case .local:
            // Local keys can use sync path
            let messageData = message.data(using: .utf8) ?? Data()
            let signatureData = try cryptoEngine.signMessage(messageData, keyData: keyData, curveCode: Int(key.curveCode))
            return CBMPCCryptoEngine.formatSignature(signatureData)

        case .server:
            guard let serverURLString = UserDefaults.standard.string(forKey: "key_\(key.id.uuidString)_server"),
                  let serverURL = URL(string: serverURLString) else {
                throw CBMPCError.serverUnreachable
            }
            let messageData = message.data(using: .utf8) ?? Data()
            let signatureData = try await cryptoEngine.signMessageRemote(
                messageData,
                deviceShare: keyData,
                curveCode: Int(key.curveCode),
                serverURL: serverURL,
                publicKey: key.publicKey
            )
            return CBMPCCryptoEngine.formatSignature(signatureData)

        case .peer:
            throw CBMPCError.transportError("Peer signing requires both devices online")
        }
    }
}
