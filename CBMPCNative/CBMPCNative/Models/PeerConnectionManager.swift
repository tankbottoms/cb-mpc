import Foundation
import MultipeerConnectivity
import CryptoKit
#if os(iOS)
import UIKit
#endif

/// Manages MultipeerConnectivity session establishment after QR pairing ceremony.
/// Uses a token derived from the ECDH shared secret (or session ID) so only the paired device connects.
class PeerConnectionManager: NSObject, ObservableObject {
    /// Must match Info.plist NSBonjourServices entry `_cbmpc._tcp`
    static let serviceType = "cbmpc"

    @Published var connectionState: ConnectionState = .disconnected {
        didSet { onStateChange?(connectionState) }
    }
    @Published var connectedPeerName: String?
    @Published var connectedAt: Date?
    var onStateChange: ((ConnectionState) -> Void)?
    var onDataReceived: ((Data, MCPeerID) -> Void)?

    enum ConnectionState: Equatable {
        case disconnected
        case searching
        case connecting
        case connected
        case failed(String)
    }

    private let localPeerID: MCPeerID
    private(set) var mcSession: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let pairingToken: String
    let partyId: UInt16  // 0 for initiator, 1 for joiner

    var remotePeerID: MCPeerID? { mcSession.connectedPeers.first }

    /// Derive a discovery token from a session UUID (SHA256 prefix -> hex)
    static func discoveryToken(from sessionId: UUID) -> String {
        let uuidBytes = withUnsafeBytes(of: sessionId.uuid) { Data($0) }
        let hash = SHA256.hash(data: uuidBytes)
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Initialize with shared secret (existing flow — post-pairing MC)
    init(sharedSecret: SharedSecret, role: PairingSession.PairingRole) {
        let tokenKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("CBMPC-discovery".utf8),
            sharedInfo: Data(),
            outputByteCount: 8
        )
        self.pairingToken = tokenKey.withUnsafeBytes { ptr in
            Data(ptr).map { String(format: "%02x", $0) }.joined()
        }
        self.partyId = role == .initiator ? 0 : 1

        #if os(iOS)
        let deviceName = UIDevice.current.name
        #else
        let deviceName = Host.current().localizedName ?? "Mac"
        #endif
        self.localPeerID = MCPeerID(displayName: deviceName)
        self.mcSession = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)

        super.init()
        self.mcSession.delegate = self
    }

    /// Initialize with pre-computed session token (for single-QR flow and reconnection)
    init(sessionToken: String, role: PairingSession.PairingRole) {
        self.pairingToken = sessionToken
        self.partyId = role == .initiator ? 0 : 1

        #if os(iOS)
        let deviceName = UIDevice.current.name
        #else
        let deviceName = Host.current().localizedName ?? "Mac"
        #endif
        self.localPeerID = MCPeerID(displayName: deviceName)
        self.mcSession = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)

        super.init()
        self.mcSession.delegate = self
    }

    func startSearching() {
        connectionState = .searching

        let discoveryInfo = ["token": pairingToken]

        advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: Self.serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        browser = MCNearbyServiceBrowser(
            peer: localPeerID,
            serviceType: Self.serviceType
        )
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    /// Send raw data to connected peer
    func sendData(_ data: Data) throws {
        guard let peer = remotePeerID else {
            throw NSError(domain: "PeerConnectionManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No connected peer"])
        }
        try mcSession.send(data, toPeers: [peer], with: .reliable)
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
        connectionState = .disconnected
    }

    private var session: MCSession { mcSession }

    deinit {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
    }
}

// MARK: - MCSessionDelegate

extension PeerConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectionState = .connected
                self.connectedPeerName = peerID.displayName
                self.connectedAt = Date()
                self.advertiser?.stopAdvertisingPeer()
                self.browser?.stopBrowsingForPeers()
            case .connecting:
                self.connectionState = .connecting
            case .notConnected:
                self.connectedAt = nil
                if case .connected = self.connectionState {
                    self.connectionState = .failed("Peer disconnected")
                }
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.onDataReceived?(data, peerID)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PeerConnectionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, mcSession)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.connectionState = .failed("Advertising failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PeerConnectionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        guard let token = info?["token"], token == pairingToken else { return }
        // Only initiator (party 0) sends invitations to avoid duplicates
        if partyId == 0 {
            browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 30)
            DispatchQueue.main.async {
                self.connectionState = .connecting
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.connectionState = .failed("Browse failed: \(error.localizedDescription)")
        }
    }
}
