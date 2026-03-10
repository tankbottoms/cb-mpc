# 2-Party ECDSA Signing Implementation Design

**Date:** March 10, 2026
**Version:** v0.17.0
**Scope:** Device+Device and Device+Server 2-party ECDSA-2PC with Keychain share storage

---

## Overview

This design specifies the v0.17 MVP for 2-party threshold signing on CB-MPC iOS app. Two distinct but architecturally similar flows:

1. **Device+Device**: Two personal devices run DKG locally, each stores its share in Keychain
2. **Device+Server**: Single device + Cloudflare key server coordinate 2-party DKG

Both flows leverage existing pairing infrastructure (QR code → MultipeerConnectivity) and produce shares suitable for ECDSA signing. The implementation prioritizes security (Keychain + SecureEnclave), simplicity (reuse existing coordinators), and reliability (error handling, timeouts, recovery).

---

## Architecture

### Data Structures

#### CeremonySession
Encapsulates a 2-party DKG/signing ceremony:
```swift
struct CeremonySession: Identifiable {
    let id: UUID
    let type: CeremonyType  // .dkg, .signing
    let participantMode: ParticipantMode  // .device, .server
    let localPartyId: Int  // 0 or 1

    var state: CeremonyState  // .initialized, .committed, .signed, .complete, .failed
    var error: String?
    var startedAt: Date
    var completedAt: Date?

    // DKG-specific
    var publicKey: String?  // hex-encoded compressed pubkey
    var shareId: String?  // keychain identifier

    // Signing-specific
    var messageHash: Data?
    var signature: String?  // base64-encoded r||s
}

enum ParticipantMode {
    case device  // Device+Device or Device+Server as primary
    case server  // Device+Server only
}

enum CeremonyState {
    case initialized
    case committed
    case signed
    case complete
    case failed(String)
}
```

#### KeyShare
Represents a stored key share in Keychain:
```swift
struct KeyShare: Codable, Identifiable {
    let id: String  // Keychain item identifier
    let keyId: UUID  // Public key reference
    let partyId: Int  // 0 or 1
    let ceremonyType: String  // "device_device" or "device_server"
    let createdAt: Date
    let publicKey: String  // hex, for reference

    // Metadata for recovery/discovery
    var backupTokenUSBC: String?  // USB-C export token if backed up
    var iCloudBackedUp: Bool = false
}
```

### Component Responsibilities

#### CeremonyCoordinator (new)
Orchestrates 2-party ceremonies. Handles:
- Session lifecycle (init → commitment exchange → signing → completion)
- State transitions and error handling
- Integration with PeerConnectionManager (Device+Device) or ServerAPIClient (Device+Server)
- Publishing to UI (Published<CeremonySession>)

#### KeyShareManager (new)
Manages Keychain storage and recovery:
- Store/retrieve shares from Keychain with SecureEnclave
- Generate Keychain identifiers
- Handle USB-C export encoding/decoding
- Provide iCloud backup metadata

#### ServerDKGCoordinator (enhanced)
Extended to support Device+Server flow:
- Call server `/ceremonies/dkg` endpoint
- Handle server-side commitments
- Coordinate local DKG after receiving server parameters

#### PeerConnectionManager (already exists)
Used for Device+Device:
- `onDataReceived` callback receives commitment messages
- `sendData()` transmits device's contributions
- Connection lifecycle tracked in PairingManager

---

## Flows

### Device+Device DKG Flow

```
Device A (initiator)          Device B (responder)
     |                              |
     | QR code generated            |
     |------ QR scanned ----------->|
     |                              |
     | MultipeerConnectivity        |
     |<----- connection ------->|
     |                              |
     | createDKGSession()           |
     | localPartyId = 0             |
     |                              |
     |------ commitments A -------->| createDKGSession()
     |                              | localPartyId = 1
     |                              |
     |<----- commitments B ---------|
     |                              |
     | runDKG() → share A           | runDKG() → share B
     | storeInKeychain()            | storeInKeychain()
     |                              |
     | publishKey(pubkey)           | publishKey(pubkey)
     |                              |
```

**Key Steps:**
1. Initiator shows QR (session ID + pubkey + device name)
2. Responder scans, connects via MC
3. Both derive connection token from shared secret
4. Initiator creates CeremonySession, broadcasts to responder via MC
5. Both run local ECDSA-2PC DKG (via libcbmpc C++)
6. Exchange commitments and partial keys over MC
7. Each computes its share, stores in Keychain
8. Both publish key to KeyStore (same pubkey reference)

**Error Handling:**
- Connection timeout → show "Device disconnected" error
- DKG timeout → cancel ceremony, notify user
- Keychain store fails → retry with user prompt

### Device+Server DKG Flow

```
Device                         Key Server
  |                                 |
  | registerDevice()                |
  | (if new device)                 |
  |-------------------------------->|
  |<--------- deviceId -------------|
  |                                 |
  | initiateDKG()                   |
  | (POST /ceremonies/dkg)          |
  |-------------------------------->|
  |<----- ceremonyId, S_commitments-|
  |                                 |
  | runDKG(S_commitments)           |
  | → share_device, commitments_d   |
  |                                 |
  | sendCommitments_d()             |
  | (PUT /ceremonies/{id}/commits)  |
  |-------------------------------->|
  |<------ complete --------|
  |                         |
  | storeInKeychain(share)  |
  |                         |
```

**Key Steps:**
1. Device initiates DKG request to server (if not already registered)
2. Server generates its DKG parameters, returns commitments
3. Device runs ECDSA-2PC locally with server's commitments
4. Device transmits its commitments to server
5. Device computes its share, stores in Keychain
6. Server derives and stores its encrypted share in vault
7. Both agree on public key; device records it in KeyStore

**Error Handling:**
- Server 500 → retry with exponential backoff
- Device timeout → mark ceremony failed, allow retry
- Keychain store fails → retry

### Signing Flow (Both Scenarios)

```
Device A / Device (primary)    Device B / Server (secondary)
     |                              |
     | selectKey(pubkey)            |
     | createSigningCeremony()      |
     |                              |
     | connect() [if Device+Device] |
     |<----- connection ------->|
     |                              |
     | retrieveShare()              |
     | → share_A from Keychain      |
     |                              |
     |------ sign_request -------->| retrieveShare()
     |                              | → share_B from vault
     |                              |
     | computeSignature(msg, share) |
     |<----- partial_sig B ---------|
     |                              |
     | combine(sig_A, sig_B)        |
     | → final signature            |
     |                              |
```

**Key Steps:**
1. User selects key from KeyDashboard
2. App creates CeremonySession (signing type)
3. For Device+Device: reconnect via MC using discoveryToken or PairingToken
4. For Device+Server: call server signing endpoint
5. Both parties retrieve their shares from secure storage
6. Exchange signing contributions
7. Final device combines and returns signature

---

## Share Storage & Recovery

### Keychain Storage
- **Item class**: `kSecClassGenericPassword`
- **Access**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (isolated per device)
- **SecureEnclave**: `kSecAttrTokenIDSecureEnclave` if available (iPhone 5S+)
- **Key format**: Raw bytes (32-byte share for secp256k1)
- **Identifier**: `cb-mpc.share.{keyId}.{partyId}`

### Device Recovery (Device+Device)
- **Primary**: iCloud Keychain backup (automatic if user enables)
- **Manual**: USB-C export (encrypted with Device UID + PIN) with strong warning
- **Limitations**: If one device lost and iCloud not enabled, that share is unrecoverable (by design — enforces security)

### Device Recovery (Device+Server)
- **Primary**: Device Keychain (protected by passcode/biometric)
- **Secondary**: Server-side encrypted backup (user can restore to new device)
- **Advantage**: Server share recovery mitigates single-device loss

### USB-C Export (Future, v0.17 Optional)
- User can export to USB-C as QR code (base64-encoded, encrypted with device UID + timestamp)
- Export triggered from Settings or Key Detail view
- Strong UX warning: "Share is encrypted but discoverable with device UID"
- Recovery: re-import from USB-C by scanning QR code

---

## Error Handling & Recovery

### Connection Failures
- **Device+Device**: MultipeerConnectivity connection drops
  - Auto-retry up to 3 times (exponential backoff)
  - Show "Reconnect?" dialog after 3 failures
  - Cancel ceremony if user dismisses

- **Device+Server**: Network/server unavailable
  - Retry with 1s, 2s, 4s delays (max 3x)
  - Show error: "Server unavailable, try again later"
  - Allow manual retry

### DKG Timeouts
- Each party waits 30s for message
- After timeout, mark ceremony failed
- UI shows: "Ceremony timed out, start over"
- No state persisted (fresh session next time)

### Keychain Errors
- Store fails: show "Failed to save share" + retry button
- Retrieve fails: show "Failed to unlock share, try again" + allow passcode re-entry
- Both are recoverable states

### Signing Failures
- If one party fails to produce signature: mark ceremony failed
- Partial signatures are discarded (not cached)
- User can retry immediately

---

## Implementation Priorities

### Phase 1: Foundation (Critical)
- [ ] CeremonyCoordinator class with state machine
- [ ] KeyShareManager with Keychain integration
- [ ] ServerDKGCoordinator enhancements (Device+Server)
- [ ] Unit tests for DKG/signing flows

### Phase 2: Device+Device (Core)
- [ ] Update PeerConnectionManager to handle commitment messages
- [ ] Implement commitment exchange over MC
- [ ] Integration test: two devices complete DKG
- [ ] UI: ceremony status screen

### Phase 3: Device+Server (Core)
- [ ] Key server DKG endpoints (`POST /ceremonies/dkg`, `PUT /ceremonies/{id}/commits`)
- [ ] ServerAPIClient integration
- [ ] Integration test: device + server complete DKG
- [ ] UI: server status screen

### Phase 4: Signing & Polish
- [ ] Signing ceremony flows (both scenarios)
- [ ] Share retrieval and signature composition
- [ ] Error recovery UI (reconnect, retry, cancel)
- [ ] E2E testing with real devices/server

### Phase 5: Documentation & Release
- [ ] User docs: "How to create 2-party keys"
- [ ] Troubleshooting guide
- [ ] Build & submit to App Store (v0.17.0)

---

## Testing Strategy

### Unit Tests
- CeremonySession state transitions
- KeyShareManager Keychain operations
- Share encoding/decoding

### Integration Tests
- Two real devices: QR pairing → DKG → verify both have compatible shares
- Device + Server: REST calls → DKG → verify signatures
- Signing: retrieve shares → sign message → verify with public key

### Manual Testing Checklist
- [ ] Device A + Device B: complete DKG, both sign same message, verify
- [ ] Device + Server: complete DKG, sign message, verify
- [ ] Connection drop mid-DKG: recover gracefully
- [ ] Keychain full: handle error gracefully
- [ ] iCloud backup: verify shares sync to new device
- [ ] USB-C export: export share, import to new device (if implemented)

---

## Success Criteria

- ✓ Two devices can pair and create a 2-party key via DKG
- ✓ Device + Server can create a 2-party key via REST coordination
- ✓ Both shares can be retrieved from Keychain and used to sign
- ✓ Signatures verify with the public key
- ✓ Connection drops handled gracefully with user-facing recovery options
- ✓ Shares are protected in Keychain (SecureEnclave when available)
- ✓ App builds and runs on 4 test devices without crashes
- ✓ No unencrypted shares appear in logs or temporary files

---

## Future Enhancements (Post-v0.17)

- [ ] 3-party and n-party ceremonies with flexible thresholds
- [ ] AND/OR access structures for multi-device scenarios
- [ ] USB-C export/import for emergency recovery
- [ ] iCloud Keychain sync for multi-device key management
- [ ] Hardware security key support (YubiKey, etc.)
- [ ] Schnorr signatures and other protocols
