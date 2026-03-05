import Foundation
import CoreData

// MARK: - Enums

enum KeyType: String, CaseIterable {
    case simple = "simple"
    case hdMaster = "hdMaster"
    case hdChild = "hdChild"
}

enum StorageLocation: String, CaseIterable {
    case secureEnclave = "secureEnclave"
    case keychain = "keychain"
}

// MARK: - Swift Model: ManagedKey

struct ManagedKey: Identifiable {
    let id: UUID
    let name: String
    let publicKey: String
    let keyType: KeyType
    let curveCode: Int32
    let derivationPath: String?
    let parentKeyId: UUID?
    let storageLocation: StorageLocation
    let createdAt: Date
    let lastUsedAt: Date?
    let isBackedUp: Bool
    var signingRecords: [SigningRecord] = []

    var publicKeyDisplay: String {
        String(publicKey.prefix(16)) + "..."
    }

    var displayKeyType: String {
        switch keyType {
        case .simple:
            return "Simple Key"
        case .hdMaster:
            return "HD Master"
        case .hdChild:
            return "HD Child"
        }
    }

    var displayStorageLocation: String {
        switch storageLocation {
        case .secureEnclave:
            return "Secure Enclave"
        case .keychain:
            return "Keychain"
        }
    }
}

// MARK: - Swift Model: SigningRecord

struct SigningRecord: Identifiable {
    let id: UUID
    let messageHash: String
    let signature: String
    let timestamp: Date
    let verified: Bool

    var messageHashDisplay: String {
        String(messageHash.prefix(16)) + "..."
    }

    var signatureDisplay: String {
        String(signature.prefix(20)) + "..."
    }
}

// MARK: - CoreData to Swift Conversions

func managedKeyToModel(_ object: NSManagedObject) -> ManagedKey {
    return ManagedKey(
        id: object.value(forKey: "id") as? UUID ?? UUID(),
        name: object.value(forKey: "name") as? String ?? "Unknown Key",
        publicKey: object.value(forKey: "publicKey") as? String ?? "",
        keyType: KeyType(rawValue: object.value(forKey: "keyType") as? String ?? "simple") ?? .simple,
        curveCode: object.value(forKey: "curveCode") as? Int32 ?? 714,
        derivationPath: object.value(forKey: "derivationPath") as? String,
        parentKeyId: object.value(forKey: "parentKeyId") as? UUID,
        storageLocation: StorageLocation(rawValue: object.value(forKey: "storageLocation") as? String ?? "keychain") ?? .keychain,
        createdAt: object.value(forKey: "createdAt") as? Date ?? Date(),
        lastUsedAt: object.value(forKey: "lastUsedAt") as? Date,
        isBackedUp: object.value(forKey: "isBackedUp") as? Bool ?? false,
        signingRecords: []
    )
}

func signingRecordToModel(_ object: NSManagedObject) -> SigningRecord {
    return SigningRecord(
        id: object.value(forKey: "id") as? UUID ?? UUID(),
        messageHash: object.value(forKey: "messageHash") as? String ?? "",
        signature: object.value(forKey: "signature") as? String ?? "",
        timestamp: object.value(forKey: "timestamp") as? Date ?? Date(),
        verified: object.value(forKey: "verified") as? Bool ?? false
    )
}

// MARK: - Swift to CoreData Conversions

func saveKeyToEntity(_ key: ManagedKey, in context: NSManagedObjectContext) {
    let entityDescription = NSEntityDescription.entity(forEntityName: "ManagedKeyEntity", in: context)
    let entity = NSManagedObject(entity: entityDescription!, insertInto: context)
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

func saveRecordToEntity(_ record: SigningRecord, in context: NSManagedObjectContext) {
    let entityDescription = NSEntityDescription.entity(forEntityName: "SigningRecordEntity", in: context)
    let entity = NSManagedObject(entity: entityDescription!, insertInto: context)
    entity.setValue(record.id, forKey: "id")
    entity.setValue(record.messageHash, forKey: "messageHash")
    entity.setValue(record.signature, forKey: "signature")
    entity.setValue(record.timestamp, forKey: "timestamp")
    entity.setValue(record.verified, forKey: "verified")
}
