import SwiftUI
import CoreData

@main
struct CBMPCApp: App {
    let persistenceController = PersistenceController.shared

    init() {
        // Seed demo data on first launch if no keys exist
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ManagedKeyEntity")
        do {
            let results = try context.fetch(fetchRequest)
            if results.isEmpty {
                seedDemoData()
            }
        } catch {
            print("Error checking for existing keys: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppNavigation()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }

    private func seedDemoData() {
        let context = persistenceController.container.viewContext

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let (demoKeys, keyDataMap) = try DemoDataGenerator.generateRealDemoKeys()

                DispatchQueue.main.async {
                    for key in demoKeys {
                        if let keyData = keyDataMap[key.id] {
                            UserDefaults.standard.set(keyData, forKey: "key_\(key.id.uuidString)")
                        }
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

                    do {
                        try context.save()
                    } catch {
                        print("Failed to save demo data: \(error)")
                    }
                }
            } catch {
                print("Failed to generate demo keys: \(error)")
            }
        }
    }
}
