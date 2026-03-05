import Foundation

#if os(iOS)
import UIKit
#else
import Darwin
#endif

// MARK: - MPC Models

struct KeyShare: Codable, Identifiable {
    let id: String
    let publicKey: String
    let shareData: Data
    let createdAt: Date

    var publicKeyDisplay: String {
        String(publicKey.prefix(16)) + "..."
    }
}

struct MPCKey {
    let id: UUID
    let publicKey: String // Compressed public key (33 bytes hex)
    let keyShare: Data    // Serialized key share
    let curveCode: Int    // secp256k1 = 714

    init() {
        self.id = UUID()
        // Mock key generation (would call c-mpc in production)
        self.publicKey = (0..<33).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        self.keyShare = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        self.curveCode = 714 // secp256k1
    }
}

struct Transaction {
    let id: UUID
    let message: String
    let messageHash: String
    var signature: String?
    var verified: Bool?
    let createdAt: Date

    init(message: String) {
        self.id = UUID()
        self.message = message
        // Mock SHA-256 hash (would use CryptoKit in production)
        self.messageHash = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        self.signature = nil
        self.verified = nil
        self.createdAt = Date()
    }
}

struct BackupData: Codable {
    let keyShare: Data
    let publicKey: String
    let timestamp: Date
    let deviceName: String
}

// MARK: - View Models

@available(macOS 14.0, *)
@Observable
class KeyShareViewModel {
    var keyShare: MPCKey?
    var isGenerating = false
    var errorMessage: String?

    func generateKeyShare() {
        isGenerating = true
        errorMessage = nil

        // Simulate key generation delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.keyShare = MPCKey()
            self.isGenerating = false
        }
    }

    func exportKeyShare() -> Data? {
        guard let keyShare = keyShare else { return nil }
        return keyShare.keyShare
    }
}

@available(macOS 14.0, *)
@Observable
class SigningViewModel {
    var transaction: Transaction?
    var isSigning = false
    var errorMessage: String?

    func signMessage(_ message: String) {
        isSigning = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            var tx = Transaction(message: message)
            // Mock signature generation (70 hex chars = 35 bytes, typical DER signature)
            tx.signature = (0..<70).map { _ in String(format: "%x", UInt8.random(in: 0...15)) }.joined()
            tx.verified = true

            self.transaction = tx
            self.isSigning = false
        }
    }
}

@available(macOS 14.0, *)
@Observable
class BackupViewModel {
    var backupData: BackupData?
    var isExporting = false
    var errorMessage: String?

    func prepareBackup(keyShare: MPCKey) {
        isExporting = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            #if os(iOS)
            let deviceName = UIDevice.current.name
            #else
            let deviceName = Host.current().localizedName ?? "Unknown Device"
            #endif

            let backup = BackupData(
                keyShare: keyShare.keyShare,
                publicKey: keyShare.publicKey,
                timestamp: Date(),
                deviceName: deviceName
            )
            self.backupData = backup
            self.isExporting = false
        }
    }
}
