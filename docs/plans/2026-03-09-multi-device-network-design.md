# Multi-Device MPC Network + Storage Overhaul

**Date:** 2026-03-09
**Status:** Approved
**Scope:** Storage tier rename, Network tab, device pairing, key generation defaults, tab bar expansion

---

## 1. Problem Statement

The current iOS app stores both 2-party key shares on a single device in UserDefaults (unencrypted). The export destinations are mislabeled ("Secure Enclave" is actually Keychain). There is no mechanism to distribute shares across physical devices or servers, which defeats the security purpose of MPC.

The app needs:
- Honest storage tier labeling with security explanations
- A unified view of all share locations (devices, iCloud, server)
- Device pairing via QR + 6-digit PIN
- 2-party DKG as the default key generation mode
- N-party support (up to N phones + server)
- 6-tab navigation (adding Network and Transactions)

---

## 2. Storage Tiers

### 2.1 Rename Map

| Current Label | New Label | API | Security Properties |
|---|---|---|---|
| Secure Enclave | Device Keychain | `kSecClassGenericPassword`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | AES-256 encrypted at rest by iOS data protection. Tied to device hardware UID. Never leaves device. Requires device unlock (passcode/Face ID). NOT the Secure Enclave hardware coprocessor (SE only supports P-256 keys up to 256 bits; our MPC shares are 2-4KB). |
| iCloud Keychain | iCloud Keychain | `kSecAttrSynchronizable: true`, `kSecAttrAccessibleWhenUnlocked` | Apple end-to-end encrypted. Syncs across devices signed into the same Apple ID. Protected by device passcode + Apple ID password. Uses AES-256-GCM in transit, HSM-backed escrow keys at rest. |
| Storage | File Export | `UIActivityViewController` | User-managed file. Can go to Files, AirDrop, USB-C, email. No automatic encryption -- user responsible for security. |
| (new) | Paired Device | Direct mTLS connection | Share transmitted via AES-256 encrypted channel after QR + 6-digit PIN pairing ceremony. Share stored in the paired device's Device Keychain. |
| (new) | MPC Server | HTTPS/mTLS to configured endpoint | Server holds one key share. Authenticated via mTLS client certificates exchanged during server registration. Server cannot sign alone (requires quorum). |

### 2.2 Settings Explainer

New section in Settings: **Storage & Security**

Each tier gets a tappable row that expands to show:
- What it protects (key shares, keystore JSON, metadata)
- How it's encrypted (AES-256, Apple data protection class)
- What happens if device is lost
- Storage usage (bytes consumed per tier)

### 2.3 Storage Usage Display

Show per-tier usage in Settings:
```
STORAGE USAGE
Device Keychain    12.4 KB  (3 shares)
iCloud Keychain     8.2 KB  (2 shares)
UserDefaults       24.8 KB  (6 key entries)
Total              45.4 KB
```

Calculated by querying Keychain item sizes and UserDefaults key sizes.

---

## 3. Tab Bar: 6 Tabs

### 3.1 Layout

```
[ Keys ] [ Network ] [ History ] [ Transactions ] [ Demos ] [ Settings ]
```

| Tab | Icon | SF Symbol | Purpose |
|-----|------|-----------|---------|
| Keys | key | `key.fill` | Key list, detail, create, sign |
| Network | antenna | `antenna.radiowaves.left.and.right` | Device network, share locations, pairing |
| History | clock | `clock.fill` | Signing history |
| Transactions | arrows | `arrow.left.arrow.right` | Contract interaction, ABI search (Task #3) |
| Demos | play | `play.circle.fill` | Demo/testing views |
| Settings | gear | `gearshape.fill` | Configuration |

### 3.2 Tab Bar Sizing

Current capsule at 4 tabs + chevron = ~260px. At 6 tabs + chevron = ~360px. iPhone SE width = 375px. Reduce icon size from 20pt to 18pt and spacing from 20 to 14 to fit. Alternatively, use a scrollable tab bar at 7+ items.

---

## 4. Network Tab

### 4.1 Node View

The Network tab shows all share storage locations as a list of "nodes":

```
NETWORK
+------------------------------------------+
|  [*] This iPhone                         |
|      Status: Active                       |
|      Shares: 6 keys (24.8 KB)            |
|      Device Keychain: 3 shares            |
+------------------------------------------+
|  [cloud] iCloud                          |
|      Status: Synced                       |
|      Shares: 2 keys (8.2 KB)             |
|      Last sync: 2 min ago                 |
+------------------------------------------+
|  [iphone] iPad Pro                       |
|      Status: Paired (offline)             |
|      Shares: 1 key                        |
|      Paired: 2026-03-08                   |
+------------------------------------------+
|  [server] MPC Server                     |
|      Status: Connected                    |
|      URL: api.cbmpc.atsignhandle.xyz      |
|      Shares: 4 keys                       |
+------------------------------------------+

[ + Pair Device ]  [ + Add Server ]
```

### 4.2 Node Detail

Tapping a node shows:
- Full device/service info
- List of key shares held on that node
- Connection status and last seen
- Actions: Ping, Refresh shares, Remove device

### 4.3 Network Topology

For each key, show its share distribution:
```
"Main Wallet" (2-of-3)
  Share 0 -> This iPhone (Device Keychain)
  Share 1 -> iPad Pro
  Share 2 -> MPC Server
```

---

## 5. Device Pairing Ceremony

### 5.1 QR + 6-Digit PIN Flow

```
INITIATOR (Device A)                    JOINER (Device B)

1. Tap "Pair Device"                    1. Tap "Pair Device"
2. Select "Show QR Code"               2. Select "Scan QR Code"
3. Generate:                            3. Open camera
   - Session UUID
   - Ephemeral X25519 keypair
   - Encode in QR:
     {session_id, ecdh_pubkey_A,
      device_name, app_version}
                                        4. Scan QR, extract:
                                           session_id, ecdh_pubkey_A
                                        5. Generate ephemeral X25519 keypair
                                        6. Compute shared_secret =
                                           ECDH(priv_B, pub_A)
                                        7. Show 6-digit PIN:
                                           PIN = HKDF(shared_secret, "pin")[0:6]
                                        8. Show QR:
                                           {session_id, ecdh_pubkey_B}

4. Scan Device B's QR
5. Compute shared_secret =
   ECDH(priv_A, pub_B)
6. Show 6-digit PIN:
   PIN = HKDF(shared_secret, "pin")[0:6]

7. User confirms PINs match            9. User confirms PINs match
   on both screens                        on both screens

8. Derive session key:                  10. Derive session key:
   AES_key = HKDF(shared_secret,            AES_key = HKDF(shared_secret,
             "aes-256-gcm")                           "aes-256-gcm")

9. Exchange mTLS certificates           11. Exchange mTLS certificates
   over AES-256-GCM channel                over AES-256-GCM channel

10. Save paired device info             12. Save paired device info
    to Keychain                             to Keychain
```

### 5.2 Pairing Data Model

```swift
struct PairedDevice: Codable, Identifiable {
    let id: UUID
    let name: String              // "iPad Pro"
    let deviceModel: String       // "iPad14,2"
    let publicKey: Data           // X25519 long-term public key
    let certificate: Data         // mTLS client certificate
    let pairedAt: Date
    var lastSeenAt: Date?
    var isOnline: Bool
    var shareCount: Int
}
```

### 5.3 Server Registration

Similar to device pairing but simpler:
1. User enters server URL in Network tab
2. App connects via HTTPS, server returns its mTLS certificate
3. App generates client certificate, sends to server
4. Server confirms registration
5. Server appears as a node in the Network view

---

## 6. Key Generation Default Shift

### 6.1 New Default: 2-Party DKG

When creating a key, the app checks the network:

| Available Nodes | Default Behavior |
|---|---|
| This iPhone only | 2 shares: Device Keychain + iCloud Keychain |
| This iPhone + iCloud | 2 shares: Device Keychain + iCloud Keychain |
| This iPhone + Paired Device | 2 shares: This iPhone + Paired Device (true 2-party) |
| This iPhone + Paired Device + Server | 3 shares: 2-of-3 threshold |
| This iPhone + N devices + Server | N+1 shares: configurable threshold |

### 6.2 Create Key Flow (Revised)

```
CREATE KEY
[1] Name: "Main Wallet"
[2] Type: ECDSA (secp256k1) | EdDSA | HD Master
[3] Share Distribution:
    Auto (recommended)     -- app chooses based on network
    Manual                 -- user selects which nodes get shares

    Selected: 2-of-3
    [x] This iPhone        (Share 0)
    [x] iPad Pro           (Share 1)
    [x] MPC Server         (Share 2)

[4] Threshold: 2 of 3     -- slider or stepper

[ Generate Key ]
```

### 6.3 Legacy Mode

Single seed phrase and raw private key import remain available but show a warning:

```
+--------------------------------------------------+
|  [!] LEGACY MODE                                  |
|  This key is not protected by MPC. The full       |
|  private key exists in one location. Consider     |
|  creating a 2-party key instead.                  |
+--------------------------------------------------+
```

---

## 7. Encrypted Messaging (Device-to-Device)

### 7.1 Channel Encryption

After pairing, devices communicate via AES-256-GCM:
- Session key derived from ECDH shared secret
- Each message includes: nonce (12 bytes) + ciphertext + tag (16 bytes)
- Message types: DKG rounds, signing rounds, key refresh, status ping

### 7.2 Transport Options

| Transport | When | Properties |
|---|---|---|
| Local network (mDNS) | Devices on same WiFi | Low latency, no internet needed |
| Relay server | Devices on different networks | Server relays encrypted blobs, cannot read content |
| Bluetooth LE | Proximity, no WiFi | Slowest, 20-byte MTU, good for PIN confirmation |
| QR code sequence | No network at all | Manual, for initial pairing only |

---

## 8. Document Conversion

### 8.1 KEY_GENERATION_ANALYSIS.md -> Forensic Brief HTML

Convert to standalone HTML with:
- Neo-brutalist dark theme (matching visual guides)
- Forensic brief formatting: numbered sections, evidence-style citations
- Collapsible code blocks
- Fixed TOC sidebar
- Monospace throughout

### 8.2 UX_WORKFLOWS.md -> Interactive HTML

Convert to standalone HTML with:
- Same dark theme
- Flow diagrams as styled HTML tables/divs
- Collapsible sections per workflow
- Quick-jump TOC

---

## 9. Immediate Changes (Pre-Network Tab)

These can ship in the next build without the full Network architecture:

1. **Rename export destinations**: "Secure Enclave" -> "Device Keychain", add explanation text
2. **Add storage usage display** to Settings
3. **Add QR speed link** from ExportKeySheetView to Settings
4. **Convert both docs** to HTML
5. **Add 6-tab floating bar** (Network and Transactions tabs can show placeholder/coming-soon)

---

## 10. Implementation Phases

| Phase | Scope | Complexity |
|---|---|---|
| Phase 1 | Storage rename, usage display, QR speed link, doc conversion, 6-tab bar stubs | Low |
| Phase 2 | Network tab with node view (This iPhone + iCloud nodes) | Medium |
| Phase 3 | Device pairing (QR + 6-digit PIN + ECDH) | High |
| Phase 4 | 2-party DKG across paired devices | High |
| Phase 5 | Server registration + 3-party support | High |
| Phase 6 | N-party threshold + configurable quorum | High |
| Phase 7 | Transactions tab (Task #3 contract interaction) | Medium |
