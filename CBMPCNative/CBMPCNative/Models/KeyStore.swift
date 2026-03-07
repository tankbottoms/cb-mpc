import Foundation
import CoreData
import SwiftUI

// Import crypto modules
// Note: These are in the same Models folder, so they should be accessible once compiled

@MainActor
class KeyStore: NSObject, ObservableObject {
    @Published var keys: [ManagedKey] = []
    @Published var selectedKeyId: UUID?

    let persistenceController: PersistenceController
    private var fetchedResultsController: NSFetchedResultsController<NSManagedObject>?
    private let cryptoEngine = CBMPCCryptoEngine()

    init(persistenceController: PersistenceController = PersistenceController.shared) {
        self.persistenceController = persistenceController
        super.init()
        loadKeys()
    }

    func loadKeys() {
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ManagedKeyEntity")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let results = try context.fetch(fetchRequest)
            self.keys = results.map { managedKeyToModel($0) }
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
            persistenceController.save()
            loadKeys()
        } catch {
            print("Error deleting key: \(error)")
        }
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
            signingRecords: []
        )
    }

    /// Add a signing record to a key's history
    func addSigningRecord(_ record: SigningRecord, to keyId: UUID) {
        if let idx = keys.firstIndex(where: { $0.id == keyId }) {
            keys[idx].signingRecords.insert(record, at: 0)
        }
    }

    // MARK: - Cryptographic Operations

    /// Generate a real cryptographic key using DKG
    func generateCryptographicKey(name: String, keyType: KeyType) throws -> ManagedKey {
        let curveCode = 714 // secp256k1

        // Note: HD key support is limited in current implementation
        // HD Master keys use simple key generation with BIP32-style paths
        let actualKeyType: KeyType = keyType == .hdChild ? .simple : keyType

        do {
            let (publicKey, serializedKey) = try cryptoEngine.generateKey(curveCode: curveCode)
            let publicKeyHex = publicKey.map { String(format: "%02x", $0) }.joined()

            // For HD Master, set derivation path to root
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

            // Store the serialized key in a safe location (for now in userDefaults, ideally in Keychain)
            UserDefaults.standard.set(serializedKey, forKey: "key_\(managedKey.id.uuidString)")

            addKey(managedKey)
            return managedKey
        } catch {
            print("Key generation error for \(keyType): \(error)")
            throw error
        }
    }

    /// Sign a message with a stored key
    func signMessage(_ message: String, with key: ManagedKey) throws -> String {
        guard let keyData = UserDefaults.standard.data(forKey: "key_\(key.id.uuidString)") else {
            throw CBMPCError.invalidKeyData
        }

        do {
            let messageData = message.data(using: .utf8) ?? Data()
            let signatureData = try cryptoEngine.signMessage(messageData, keyData: keyData, curveCode: Int(key.curveCode))
            return CBMPCCryptoEngine.formatSignature(signatureData)
        } catch {
            throw error
        }
    }
}
