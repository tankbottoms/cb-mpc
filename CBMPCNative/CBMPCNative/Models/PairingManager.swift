import Foundation
import CryptoKit
import Security
#if os(iOS)
import UIKit
#endif

// MARK: - Paired Device Model

struct PairedDevice: Codable, Identifiable {
    let id: UUID
    let name: String
    let deviceModel: String
    let publicKey: Data           // X25519 long-term public key
    let pairedAt: Date
    var lastSeenAt: Date?
    var isOnline: Bool
    var shareCount: Int
}

// MARK: - MPC Server Model

struct MPCServer: Codable, Identifiable {
    let id: UUID
    let name: String
    let url: String
    let registeredAt: Date
    var lastSeenAt: Date?
    var isOnline: Bool
    var shareCount: Int
    var apiVersion: String?
}

// MARK: - Pairing Session

struct PairingSession {
    let sessionId: UUID
    let localKeyPair: Curve25519.KeyAgreement.PrivateKey
    let role: PairingRole
    var remotePublicKey: Curve25519.KeyAgreement.PublicKey?
    var sharedSecret: SharedSecret?
    var pin: String?
    var sessionKey: SymmetricKey?

    enum PairingRole {
        case initiator
        case joiner
    }

    init(role: PairingRole) {
        self.sessionId = UUID()
        self.localKeyPair = Curve25519.KeyAgreement.PrivateKey()
        self.role = role
    }

    /// QR payload for initiator (Device A shows this)
    var initiatorQRPayload: Data {
        var payload = Data()
        // Session ID (16 bytes)
        let uuidBytes = withUnsafeBytes(of: sessionId.uuid) { Data($0) }
        payload.append(uuidBytes)
        // Public key (32 bytes)
        payload.append(localKeyPair.publicKey.rawRepresentation)
        // Device name (variable, UTF-8)
        #if os(iOS)
        let deviceName = UIDevice.current.name
        #else
        let deviceName = Host.current().localizedName ?? "Mac"
        #endif
        payload.append(Data(deviceName.utf8))
        return payload
    }

    /// Compute shared secret from remote public key
    mutating func computeSharedSecret(remotePublicKey: Curve25519.KeyAgreement.PublicKey) throws {
        self.remotePublicKey = remotePublicKey
        self.sharedSecret = try localKeyPair.sharedSecretFromKeyAgreement(with: remotePublicKey)

        // Derive 6-digit PIN
        let pinKey = sharedSecret!.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("CBMPC-pairing-pin".utf8),
            sharedInfo: Data(),
            outputByteCount: 4
        )
        let pinData = pinKey.withUnsafeBytes { Data($0) }
        let pinValue = pinData.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(as: UInt32.self)
        } % 1_000_000
        self.pin = String(format: "%06d", pinValue)

        // Derive session key for encrypted communication
        self.sessionKey = sharedSecret!.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("CBMPC-aes-256-gcm".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )
    }
}

// MARK: - Pairing Manager

class PairingManager: ObservableObject {
    static let shared = PairingManager()

    @Published var pairedDevices: [PairedDevice] = []
    @Published var servers: [MPCServer] = []

    private let devicesKey = "xyz.atsignhandle.cb-mpc.paired-devices"
    private let serversKey = "xyz.atsignhandle.cb-mpc.mpc-servers"

    init() {
        loadPairedDevices()
        loadServers()
    }

    // MARK: - Paired Devices

    func loadPairedDevices() {
        guard let data = UserDefaults.standard.data(forKey: devicesKey),
              let devices = try? JSONDecoder().decode([PairedDevice].self, from: data) else {
            pairedDevices = []
            return
        }
        pairedDevices = devices
    }

    func savePairedDevices() {
        if let data = try? JSONEncoder().encode(pairedDevices) {
            UserDefaults.standard.set(data, forKey: devicesKey)
        }
    }

    func addPairedDevice(_ device: PairedDevice) {
        pairedDevices.append(device)
        savePairedDevices()
    }

    func removePairedDevice(_ device: PairedDevice) {
        pairedDevices.removeAll { $0.id == device.id }
        savePairedDevices()
    }

    // MARK: - MPC Servers

    func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: serversKey),
              let servers = try? JSONDecoder().decode([MPCServer].self, from: data) else {
            self.servers = []
            return
        }
        self.servers = servers
    }

    func saveServers() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: serversKey)
        }
    }

    func addServer(_ server: MPCServer) {
        servers.append(server)
        saveServers()
    }

    func removeServer(_ server: MPCServer) {
        servers.removeAll { $0.id == server.id }
        saveServers()
    }

    func pingServer(_ server: MPCServer, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: server.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            completion(false, "Invalid URL")
            return
        }

        let healthURL = url.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(false, "No response")
                    return
                }
                if httpResponse.statusCode == 200 {
                    var version: String?
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        version = json["version"] as? String
                    }
                    completion(true, version)
                } else {
                    completion(false, "HTTP \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
}
