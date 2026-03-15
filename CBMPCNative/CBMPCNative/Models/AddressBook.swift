import Foundation
import Combine

// MARK: - AddressEntry

struct AddressEntry: Codable, Identifiable {
    let id: UUID
    var label: String
    var address: String
    var chainId: String
    let createdAt: Date
    var lastUsedAt: Date?

    init(id: UUID = UUID(), label: String, address: String, chainId: String = "1", createdAt: Date = Date(), lastUsedAt: Date? = nil) {
        self.id = id
        self.label = label
        self.address = address.hasPrefix("0x") ? address : "0x\(address)"
        self.chainId = chainId
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

// MARK: - AddressBook

@MainActor
class AddressBook: ObservableObject {
    @Published var entries: [AddressEntry] = []

    private static let storageKey = "addressBook"

    init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        do {
            entries = try JSONDecoder().decode([AddressEntry].self, from: data)
        } catch {
            print("Error loading address book: \(error)")
            entries = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            print("Error saving address book: \(error)")
        }
    }

    // MARK: - CRUD

    @discardableResult
    func add(label: String, address: String, chainId: String = "1") -> AddressEntry {
        let entry = AddressEntry(label: label, address: address, chainId: chainId)
        entries.append(entry)
        save()
        return entry
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func update(id: UUID, label: String, address: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].label = label
        entries[idx].address = address.hasPrefix("0x") ? address : "0x\(address)"
        save()
    }

    func markUsed(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].lastUsedAt = Date()
        save()
    }

    // MARK: - Queries

    /// Entries sorted by most recently used first, then alphabetically by label.
    var sorted: [AddressEntry] {
        entries.sorted { lhs, rhs in
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (l?, r?):
                return l > r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
        }
    }

    /// Filter entries whose label or address contains the query (case-insensitive).
    func search(_ query: String) -> [AddressEntry] {
        let q = query.lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.label.lowercased().contains(q) || $0.address.lowercased().contains(q)
        }
    }
}
