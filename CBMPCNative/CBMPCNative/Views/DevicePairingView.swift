import SwiftUI
import CryptoKit
import CoreImage.CIFilterBuiltins
import MultipeerConnectivity
#if os(iOS)
import UIKit
import AVFoundation
#endif

// MARK: - Pairing Entry Point

struct DevicePairingView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var pairingManager = PairingManager.shared

    @State private var selectedRole: PairingSession.PairingRole?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DEVICE PAIRING")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text("Pair two devices to enable true 2-party MPC. Each device holds one key share -- neither can sign alone.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.05))
                .cornerRadius(6)

                VStack(spacing: 12) {
                    Button(action: { selectedRole = .initiator }) {
                        HStack {
                            Image(systemName: "qrcode")
                                .font(.system(size: 24))
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Show QR Code")
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                Text("Display a QR code for the other device to scan")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button(action: { selectedRole = .joiner }) {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 24))
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Scan QR Code")
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                Text("Scan the QR code shown on the other device")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("HOW IT WORKS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    ForEach(Array([
                        "Device A shows QR code (session ID + public key + name)",
                        "Device B scans QR and both start peer-to-peer discovery",
                        "Public keys are exchanged over local network",
                        "ECDH computes a shared secret (never transmitted)",
                        "6-digit PIN derived from shared secret -- verify on both screens"
                    ].enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                                .frame(width: 16)
                            Text(step)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(.gray.opacity(0.05))
                .cornerRadius(6)

                Spacer()
            }
            .padding(16)
            .navigationTitle("Pair Device")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: Binding(
                get: { selectedRole.map { PairingRoleWrapper(role: $0) } },
                set: { selectedRole = $0?.role }
            )) { wrapper in
                PairingSessionView(role: wrapper.role, pairingManager: pairingManager, onComplete: {
                    selectedRole = nil
                    dismiss()
                })
            }
        }
    }
}

// Wrapper to make PairingRole identifiable for sheet
struct PairingRoleWrapper: Identifiable {
    let role: PairingSession.PairingRole
    var id: String { role == .initiator ? "initiator" : "joiner" }
}

// MARK: - Pairing Session View (Single-QR Flow)

struct PairingSessionView: View {
    let role: PairingSession.PairingRole
    let pairingManager: PairingManager
    let onComplete: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var session: PairingSession
    @State private var step: PairingStep = .qrExchange
    @State private var remoteName: String = ""
    @State private var remoteModel: String = ""
    @State private var errorMessage: String?
    @State private var isGeneratingSharedKey = false
    @State private var sharedKeyError: String?
    @State private var sharedKeyGenerated = false
    @State private var peerConnection: PeerConnectionManager?
    @State private var mcState: PeerConnectionManager.ConnectionState = .disconnected
    @State private var pairedDeviceId: UUID?

    /// MC data channel message prefix
    private static let mcDataPrefix: UInt8 = 0xCB

    enum PairingStep {
        case qrExchange
        case confirmPIN
        case paired
    }

    init(role: PairingSession.PairingRole, pairingManager: PairingManager, onComplete: @escaping () -> Void) {
        self.role = role
        self.pairingManager = pairingManager
        self.onComplete = onComplete
        self._session = State(initialValue: PairingSession(role: role))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Step indicator
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(stepIndex >= i ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal, 16)

                switch step {
                case .qrExchange:
                    qrExchangeView
                case .confirmPIN:
                    confirmPINView
                case .paired:
                    pairedView
                }
            }
            .navigationTitle(stepTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        peerConnection?.stop()
                        dismiss()
                    }
                }
            }
        }
    }

    private var stepIndex: Int {
        switch step {
        case .qrExchange: return 0
        case .confirmPIN: return 1
        case .paired: return 2
        }
    }

    private var stepTitle: String {
        switch step {
        case .qrExchange: return role == .initiator ? "Show QR" : "Scan QR"
        case .confirmPIN: return "Verify PIN"
        case .paired: return "Paired"
        }
    }

    // MARK: - Step Views

    /// Initiator: show QR + start MC browse
    /// Joiner: show scanner; on scan, start MC advertise
    private var qrExchangeView: some View {
        VStack(spacing: 16) {
            if role == .initiator {
                Text("Show this QR code to the other device")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                qrCodeImage(for: session.initiatorQRPayload)

                Text("Session: \(session.sessionId.uuidString.prefix(8))...")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)

                // MC searching status
                mcSearchingStatusView
            } else {
                Text("Scan the QR code shown on the other device")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                #if os(iOS)
                PairingScannerView { data in
                    handleInitiatorQR(data)
                }
                .frame(height: 300)
                .cornerRadius(8)
                #else
                Text("Camera scanning requires iOS")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(height: 300)
                #endif

                if peerConnection != nil {
                    mcSearchingStatusView
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding(16)
        .onAppear {
            if role == .initiator {
                startMCForInitiator()
            }
        }
    }

    @ViewBuilder
    private var mcSearchingStatusView: some View {
        switch mcState {
        case .searching:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text("Searching for peer on local network...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(.blue.opacity(0.05))
            .cornerRadius(6)
        case .connecting:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text("Connecting to peer...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.orange)
            }
            .padding(10)
            .background(.orange.opacity(0.05))
            .cornerRadius(6)
        case .failed(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                Text(msg)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
            }
            .padding(10)
            .background(.red.opacity(0.05))
            .cornerRadius(6)
        default:
            EmptyView()
        }
    }

    private var confirmPINView: some View {
        VStack(spacing: 24) {
            Text("Verify this PIN matches on both devices")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)

            if let pin = session.pin {
                HStack(spacing: 12) {
                    ForEach(Array(pin.enumerated()), id: \.offset) { _, digit in
                        Text(String(digit))
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .frame(width: 44, height: 56)
                            .background(.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }

            VStack(spacing: 8) {
                Text("Do the PINs match?")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("No, Cancel") {
                        peerConnection?.stop()
                        dismiss()
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .buttonStyle(.bordered)

                    Button("Yes, Confirm") {
                        completePairing()
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .buttonStyle(.borderedProminent)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("SECURITY")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("This PIN was derived from an ECDH shared secret. If the PINs don't match, a man-in-the-middle attack may be in progress. Cancel immediately.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(.orange.opacity(0.05))
            .cornerRadius(6)

            Spacer()
        }
        .padding(16)
    }

    private var pairedView: some View {
        VStack(spacing: 20) {
            if sharedKeyGenerated {
                Image(systemName: "key.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)

                Text("Shared Key Created")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)

                Text("Device Paired")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
            }

            if !remoteName.isEmpty {
                VStack(spacing: 2) {
                    Text(remoteName)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.secondary)
                    if !remoteModel.isEmpty {
                        Text(remoteModel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if sharedKeyGenerated {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Both devices now hold one key share each.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.blue)
                    Text("Neither device can sign alone — both must cooperate.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.blue)
                }
                .padding(10)
                .background(.blue.opacity(0.05))
                .cornerRadius(6)
            } else if isGeneratingSharedKey {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Generating shared key on both devices...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(.blue.opacity(0.05))
                .cornerRadius(6)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Encrypted channel established (AES-256-GCM)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("Shared key generation will start automatically...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(.green.opacity(0.05))
                .cornerRadius(6)
            }

            if let error = sharedKeyError {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
                    .padding(8)
                    .background(.red.opacity(0.05))
                    .cornerRadius(6)

                Button("Retry") {
                    generateSharedKey()
                }
                .font(.system(size: 13, design: .monospaced))
                .buttonStyle(.bordered)
            }

            if sharedKeyGenerated || sharedKeyError != nil {
                Button("Done") {
                    onComplete()
                    dismiss()
                }
                .font(.system(size: 14, design: .monospaced))
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(16)
        .onAppear {
            // Auto-start DKG when paired view appears — runs on both devices simultaneously
            if mcState == .connected && !isGeneratingSharedKey && !sharedKeyGenerated {
                generateSharedKey()
            }
        }
        .onChange(of: mcState) {
            // If MC connects after view appeared (e.g. reconnect), auto-start DKG
            if case .connected = mcState, !isGeneratingSharedKey, !sharedKeyGenerated {
                generateSharedKey()
            }
        }
    }

    @ViewBuilder
    private var mcConnectionStatusView: some View {
        switch mcState {
        case .disconnected:
            EmptyView()
        case .searching:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text("Searching for peer on local network...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(.blue.opacity(0.05))
            .cornerRadius(6)
        case .connecting:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text("Connecting to peer...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.orange)
            }
            .padding(10)
            .background(.orange.opacity(0.05))
            .cornerRadius(6)
        case .connected:
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text("Peer connected — ready for shared key generation")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.green)
            }
            .padding(10)
            .background(.green.opacity(0.05))
            .cornerRadius(6)
        case .failed(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                Text(msg)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
            }
            .padding(10)
            .background(.red.opacity(0.05))
            .cornerRadius(6)
        }
    }

    private func generateSharedKey() {
        guard let conn = peerConnection,
              let remotePeer = conn.remotePeerID else {
            sharedKeyError = "No peer connection available"
            return
        }

        isGeneratingSharedKey = true
        sharedKeyError = nil

        let mcSession = conn.mcSession
        let localPartyId = conn.partyId

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try PeerDKGCoordinator.generateKey(
                    session: mcSession,
                    remotePeerID: remotePeer,
                    localPartyId: localPartyId,
                    curveCode: 714
                )

                let publicKeyHex = result.publicKey.map { String(format: "%02x", $0) }.joined()

                DispatchQueue.main.async {
                    let keyId = UUID()
                    let timestamp = AppDateFormat.string(from: Date())
                    let shortAddr = "0x\(String(publicKeyHex.prefix(4)))...\(String(publicKeyHex.suffix(4)))"

                    let managedKey = ManagedKey(
                        id: keyId,
                        name: "\(shortAddr) peer \(timestamp)",
                        publicKey: publicKeyHex,
                        keyType: .simple,
                        curveCode: 714,
                        derivationPath: nil,
                        parentKeyId: nil,
                        storageLocation: .secureEnclave,
                        createdAt: Date(),
                        lastUsedAt: nil,
                        isBackedUp: false,
                        signingRecords: []
                    )

                    UserDefaults.standard.set(result.localShare, forKey: "key_\(keyId.uuidString)")
                    TransportOrigin.save(.peer, for: keyId)
                    if let devId = self.pairedDeviceId {
                        TransportOrigin.saveCoSigner(devId.uuidString, for: keyId)
                    }

                    NotificationCenter.default.post(
                        name: Notification.Name("CBMPCAddPeerKey"),
                        object: managedKey
                    )

                    self.isGeneratingSharedKey = false
                    self.sharedKeyGenerated = true

                    // Update paired device share count
                    if let devId = self.pairedDeviceId,
                       let idx = self.pairingManager.pairedDevices.firstIndex(where: { $0.id == devId }) {
                        self.pairingManager.pairedDevices[idx].shareCount += 1
                        self.pairingManager.savePairedDevices()
                    }

                    #if os(iOS)
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.success)
                    #endif
                }
            } catch {
                DispatchQueue.main.async {
                    self.sharedKeyError = "Peer DKG failed: \(error.localizedDescription)"
                    self.isGeneratingSharedKey = false
                }
            }
        }
    }

    // MARK: - Single-QR Flow: MC Setup

    /// Initiator: start MC browsing with session-derived token
    private func startMCForInitiator() {
        let token = PeerConnectionManager.discoveryToken(from: session.sessionId)
        let conn = PeerConnectionManager(sessionToken: token, role: .initiator)
        conn.onStateChange = { state in
            self.mcState = state
        }
        conn.onDataReceived = { data, _ in
            handleJoinerMCData(data)
        }
        self.peerConnection = conn
        conn.startSearching()
    }

    /// Joiner: after scanning QR, start MC advertising with session-derived token
    private func startMCForJoiner() {
        let token = PeerConnectionManager.discoveryToken(from: session.sessionId)
        let conn = PeerConnectionManager(sessionToken: token, role: .joiner)
        conn.onStateChange = { state in
            self.mcState = state
            // When MC connects: send our public key, compute shared secret, advance to PIN
            if case .connected = state {
                sendJoinerKeyOverMC(conn)
                if let remotePub = session.remotePublicKey {
                    do {
                        try session.computeSharedSecret(remotePublicKey: remotePub)
                        #if os(iOS)
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        #endif
                        step = .confirmPIN
                    } catch {
                        errorMessage = "Key agreement failed: \(error.localizedDescription)"
                    }
                }
            }
        }
        conn.onDataReceived = { _, _ in
            // Joiner doesn't expect data back during pairing
        }
        self.peerConnection = conn
        conn.startSearching()
    }

    /// Joiner sends: 0xCB + pubkey(32) + nameLen(2 BE) + name(UTF8) + model(UTF8)
    private func sendJoinerKeyOverMC(_ conn: PeerConnectionManager) {
        var payload = Data()
        payload.append(Self.mcDataPrefix)
        payload.append(session.localKeyPair.publicKey.rawRepresentation)

        let deviceName = DeviceInfo.deviceName
        let deviceModel = DeviceInfo.modelName

        let nameData = Data(deviceName.utf8)
        var nameLen = UInt16(nameData.count).bigEndian
        payload.append(Data(bytes: &nameLen, count: 2))
        payload.append(nameData)
        payload.append(Data(deviceModel.utf8))

        do {
            try conn.sendData(payload)
        } catch {
            errorMessage = "Failed to send key: \(error.localizedDescription)"
        }
    }

    // MARK: - QR Handling

    /// Joiner scans initiator's QR: parse session + pubkey + name + model, then start MC
    private func handleInitiatorQR(_ data: Data) {
        // Parse v2: session_id(16) + pubkey(32) + nameLen(2 BE) + name(variable) + model(variable)
        // Fallback v1: session_id(16) + pubkey(32) + name(variable)
        guard data.count >= 48 else {
            errorMessage = "Invalid QR code"
            return
        }

        let uuidBytes = data.prefix(16)
        let pubKeyBytes = data[16..<48]
        let remaining = data.suffix(from: 48)

        // Parse session ID
        let uuid = uuidBytes.withUnsafeBytes { ptr -> uuid_t in
            ptr.load(as: uuid_t.self)
        }
        // Create new session but override sessionId to match initiator
        session = PairingSession(role: .joiner)

        // Store remote public key
        guard let remotePub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: pubKeyBytes) else {
            errorMessage = "Invalid public key"
            return
        }
        session.remotePublicKey = remotePub

        // Parse name + model (v2 format with nameLen prefix)
        if remaining.count >= 2 {
            let nameLenOffset = remaining.startIndex
            let byte0 = remaining[nameLenOffset]
            let byte1 = remaining[nameLenOffset + 1]
            let nameLen = Int(UInt16(byte0) << 8 | UInt16(byte1))

            let nameStart = nameLenOffset + 2
            if nameLen <= remaining.count - 2 {
                // v2 format
                let nameEnd = nameStart + nameLen
                remoteName = String(data: remaining[nameStart..<nameEnd], encoding: .utf8) ?? "Unknown Device"
                if nameEnd < remaining.endIndex {
                    remoteModel = String(data: remaining[nameEnd...], encoding: .utf8) ?? ""
                }
            } else {
                // Fallback: treat all remaining as name (v1)
                remoteName = String(data: remaining, encoding: .utf8) ?? "Unknown Device"
            }
        } else {
            remoteName = String(data: remaining, encoding: .utf8) ?? "Unknown Device"
        }

        // Override session ID to match initiator's
        // We need to use the same session ID for MC discovery token
        session.sessionId = UUID(uuid: uuid)

        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        #endif

        // Start MC advertising with the same session-derived token
        startMCForJoiner()
    }

    /// Initiator receives joiner's pubkey + name over MC data channel
    private func handleJoinerMCData(_ data: Data) {
        // Parse: 0xCB + pubkey(32) + nameLen(2 BE) + name(UTF8) + model(UTF8)
        guard data.count >= 35, data[data.startIndex] == Self.mcDataPrefix else {
            return
        }

        let pubKeyBytes = data[(data.startIndex + 1)..<(data.startIndex + 33)]
        let remaining = data.suffix(from: data.startIndex + 33)

        guard let remotePub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: pubKeyBytes) else {
            errorMessage = "Invalid remote public key"
            return
        }

        // Parse name + model
        if remaining.count >= 2 {
            let nameLenOffset = remaining.startIndex
            let byte0 = remaining[nameLenOffset]
            let byte1 = remaining[nameLenOffset + 1]
            let nameLen = Int(UInt16(byte0) << 8 | UInt16(byte1))

            let nameStart = nameLenOffset + 2
            if nameLen <= remaining.count - 2 {
                let nameEnd = nameStart + nameLen
                remoteName = String(data: remaining[nameStart..<nameEnd], encoding: .utf8) ?? "Unknown Device"
                if nameEnd < remaining.endIndex {
                    remoteModel = String(data: remaining[nameEnd...], encoding: .utf8) ?? ""
                }
            } else {
                remoteName = String(data: remaining, encoding: .utf8) ?? "Unknown Device"
            }
        }

        // Compute shared secret and advance to PIN confirmation
        do {
            try session.computeSharedSecret(remotePublicKey: remotePub)
            #if os(iOS)
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            #endif
            step = .confirmPIN
        } catch {
            errorMessage = "Key agreement failed: \(error.localizedDescription)"
        }
    }

    private func completePairing() {
        let token = PeerConnectionManager.discoveryToken(from: session.sessionId)
        let deviceId = UUID()
        self.pairedDeviceId = deviceId

        let device = PairedDevice(
            id: deviceId,
            name: remoteName.isEmpty ? "Paired Device" : remoteName,
            deviceModel: remoteModel.isEmpty ? "iPhone" : remoteModel,
            publicKey: session.remotePublicKey?.rawRepresentation ?? Data(),
            pairedAt: Date(),
            lastSeenAt: Date(),
            isOnline: true,
            shareCount: 0,
            discoveryToken: token
        )
        pairingManager.addPairedDevice(device)

        // Register the active MC connection with PairingManager (persists after sheet dismiss)
        if let conn = peerConnection {
            pairingManager.registerConnection(conn, for: deviceId)
        }

        #if os(iOS)
        let success = UINotificationFeedbackGenerator()
        success.notificationOccurred(.success)
        #endif

        step = .paired
    }

    // MARK: - QR Code Image

    @ViewBuilder
    private func qrCodeImage(for data: Data) -> some View {
        let base64 = data.base64EncodedString()
        let ciContext = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let _ = {
            filter.message = Data(base64.utf8)
            filter.correctionLevel = "M"
        }()

        if let output = filter.outputImage,
           output.extent.size.width > 0 {
            let scale = 200.0 / output.extent.size.width
            let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            if let cgImage = ciContext.createCGImage(transformed, from: transformed.extent) {
                Image(uiImage: UIImage(cgImage: cgImage))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(12)
                    .background(.white)
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Pairing QR Scanner (reuses camera infra)

#if os(iOS)
struct PairingScannerView: UIViewControllerRepresentable {
    let onScan: (Data) -> Void

    func makeUIViewController(context: Context) -> PairingScannerVC {
        let vc = PairingScannerVC()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ vc: PairingScannerVC, context: Context) {
        vc.onScan = onScan
    }
}

class PairingScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((Data) -> Void)?
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didCapture = false

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds
        if let layer = previewLayer {
            view.layer.addSublayer(layer)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stopRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didCapture else { return }
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  readable.type == .qr,
                  let stringValue = readable.stringValue,
                  let data = Data(base64Encoded: stringValue) else { continue }
            didCapture = true
            captureSession.stopRunning()
            onScan?(data)
            return
        }
    }
}
#endif
