# CB-MPC Visual Guide Expansion Plan

**Scope**: Documentation & wireframes only. No implementation commits. Explore all 2-party/3-party/n-party permutations before deciding build order.

---

## 5 New Visual Guide Pages to Document

### 1. QR Transfer Workflow (`qr-transfer-workflow.html`)

**Why**: Show how keys move between devices via QR codes (offline-first, air-gap capable)

**Content**:
- Binary frame format overview (why chunked?)
- Compression (zlib) and encryption (AES-256-GCM) with passphrase
- QR generation from encrypted key material
- Multi-part QR sequence (Part 1/N, 2/N, 3/N...)
- Device B scanning and reassembly
- Decryption and validation
- Error recovery (corrupted frame, restart)

**Wireframes**:
- Device A: "Export Key Share" → generates passphrase → displays QR sequence (Part 1/5, 2/5, etc)
- Device B: "Import Key Share" → enters passphrase → camera view with progress (2/5 scanned)
- Success: "Share imported - Key is now 2-of-2 with Device A"

**Use Cases**:
- Initial key distribution to second device
- Key recovery from backup device
- Offline transfer (no internet needed)

**Diagram**: Timeline showing encryption → QR generation → scanning → decryption → import

---

### 2. Bluetooth MultiPeer Protocol (`bluetooth-multipeer-protocol.html`)

**Why**: Show real-time key operations via BLE (faster than QR, concurrent protocols)

**Content**:
- BLE discovery and advertisement (what's in the BLE packet?)
- Pairing handshake (passphrase QR for session ID)
- TLS certificate exchange via short QR codes (3-4 codes)
- mTLS tunnel setup
- 2-party DKG protocol execution over BLE (Round 1, 2, 3 message flow)
- Signing coordination (commitment → response → finalization)
- Disconnection and retry logic
- Performance characteristics (latency, range)

**Wireframes**:
- Device A: "Create with Device B" → BLE scan showing Device B → "Tap to pair"
- Pairing UI: Show passphrase QR code (session ID validation)
- Certificate exchange: 3 QR codes in sequence
- Connected state: "Generating key with Device B... Round 1/3 (Generating commitments)"
- Live protocol progress with phase names

**Use Cases**:
- Real-time key generation across devices
- Signing with immediate feedback
- Better UX than QR (continuous protocol)

**Diagram**: Message flow diagram showing BLE packets for each protocol round

---

### 3. Custody Models & Security Permutations (`custody-models.html`)

**Why**: Help users/architects choose the right security model for their use case

**Content**:

#### Model 1: Single Device (Development)
```
Device
├─ Share 0 (Keychain)
└─ Share 1 (Keychain)
→ Can sign alone (1-of-1)
→ NO external coordination needed
```
- **Security**: Low (device compromise = key loss)
- **Availability**: Always (offline signing)
- **Cost**: Free
- **Use Case**: Development, single user, high-frequency signing
- **Storage**: Keychain (no backup by default)
- **Backup**: Manual export to file only

#### Model 2a: Two Devices - QR Bootstrap (2-of-2)
```
Device A                Device B
├─ Share 0 (KC)   <──────→  ├─ Share 1 (KC)
└─ [KC = Keychain]          └─ [KC = Keychain]
→ Both needed to sign
→ Air-gap capable (QR transfer only)
```
- **Security**: High (share never crosses device boundary)
- **Availability**: Requires both devices online simultaneously
- **Cost**: Free (both devices user-owned)
- **Use Case**: Co-custody, offline-first, married couple, business partners
- **Storage**:
  - Device A: Share 0 in Keychain (primary), encrypted file backup to iCloud
  - Device B: Share 1 in Keychain (primary), encrypted file backup to iCloud
- **Transfer**: QR code exchange (offline, air-gap safe)
- **Backup**: Each device exports its own share as encrypted file

#### Model 2b: Two Devices - Bluetooth Real-Time (2-of-2)
```
Device A ←BLE→ Device B
├─ Share 0        ├─ Share 1
└─ (local ops)    └─ (local ops)
→ Both needed for signing
→ Real-time protocol coordination
```
- **Security**: High (same as 2a, but live protocol)
- **Availability**: Requires both devices online (but protocol is concurrent)
- **Cost**: Free
- **Use Case**: Same as 2a, but faster/better UX
- **Storage**: Same as 2a (Keychain primary)
- **Transfer**: BLE with mTLS and certificate exchange
- **Backup**: Same as 2a (encrypted file export)

#### Model 3: Two Devices + Server (2-of-3 Threshold)
```
Device A          Device B          Server
├─ Share 0        ├─ Share 1        └─ Share 2 (HSM)
└─ (KC)           └─ (KC)              (Hardware Security Module)

→ Any 2 of 3 can sign
→ Device A lost? Use Device B + Server
→ Server compromised? Use Device A + Device B
```
- **Security**: Medium-High (no single point of failure)
- **Availability**: High (one device or server can be offline)
- **Cost**: Server infrastructure + potential HSM rental
- **Use Case**: Enterprise, policy enforcement, audit trail, institutional custody
- **Storage**:
  - Devices: Share in Keychain (synced to iCloud Keychain as backup)
  - Server: Share in HSM (non-extractable, audit logging)
- **Transfer**: Network + mTLS (requires internet)
- **Backup**: Server backup provides redundancy; threshold refresh if one party lost

#### Model 4: N-Party Organization (e.g., 3-of-5 Governance)
```
Admin 1  Admin 2  Admin 3  Admin 4  Admin 5
├─Share0 ├─Share1 ├─Share2 ├─Share3 ├─Share4
└─(KC)   └─(KC)   └─(KC)   └─(KC)   └─(KC)

→ Any 3 of 5 can authorize transaction
→ Quorum-based governance
```
- **Security**: High (need consensus, no individual authority)
- **Availability**: Medium (need quorum online)
- **Cost**: All parties provide their own device
- **Use Case**: DAO treasury, multi-sig organization, corporate board approval
- **Storage**: Each admin's device stores 1 share in Keychain
- **Transfer**: Network + mTLS (all parties coordinate)
- **Backup**: Threshold refresh to onboard new admin or recover lost share

---

### 4. Key Storage Security Hierarchy (`key-storage-hierarchy.html`)

**Why**: Show storage options with security/performance/cost trade-offs

**Storage Tiers** (most secure → least secure):

#### Tier 1: Keychain (Device-Encrypted)
```
┌─────────────────────────────┐
│ iOS Keychain (Device)       │
├─────────────────────────────┤
│ Encrypted by device        │
│ Protected: Device passcode │
│ Survives reboot: YES       │
│ Extractable: NO (TEE)      │
│ Biometric lock: Optional   │
│ Cross-device: NO           │
├─────────────────────────────┤
│ Use: PRIMARY key share     │
│ Cost: Free (built-in)      │
│ Performance: Fast (<1ms)   │
│ Recovery: Import from file │
└─────────────────────────────┘
```

#### Tier 2: iCloud Keychain (Synced Encrypted)
```
┌──────────────────────────────┐
│ iCloud Keychain (Synced)     │
├──────────────────────────────┤
│ Encrypted end-to-end        │
│ Protected: iCloud pw + key  │
│ Survives device loss: YES   │
│ Extractable: NO (Apple key) │
│ Biometric lock: Device bio  │
│ Cross-device: YES (sync)    │
├──────────────────────────────┤
│ Use: BACKUP via iCloud      │
│ Cost: Free (+ iCloud storage)
│ Performance: Requires network
│ Recovery: Auto-restore on   │
│           new device        │
└──────────────────────────────┘
```

#### Tier 3: Encrypted File Export (User Passphrase)
```
┌────────────────────────────────┐
│ File System / Cloud Storage    │
├────────────────────────────────┤
│ Format: Keystore V3 JSON       │
│ Encryption: AES-256-GCM        │
│ Protected: User passphrase     │
│ Extractable: YES (file)        │
│ Biometric lock: NO             │
│ Cross-device: YES (file share) │
├────────────────────────────────┤
│ Use: COLD STORAGE / Recovery   │
│ Cost: Depends on cloud service │
│ Performance: File I/O          │
│ Recovery: Manual import        │
│ Risk: File interception,       │
│       passphrase guessing      │
└────────────────────────────────┘
```

#### Tier 4: USB-C Encrypted Backup
```
┌──────────────────────────────┐
│ USB-C Storage Device         │
├──────────────────────────────┤
│ Format: Proprietary encrypted│
│ Encryption: Device-enforced  │
│ Protected: PIN + biometric   │
│ Extractable: NO (device)     │
│ Offline: YES (air-gap safe)  │
│ Durability: 10+ years        │
├──────────────────────────────┤
│ Use: LONG-TERM BACKUP        │
│ Cost: $100-500 (hardware)    │
│ Performance: USB speeds      │
│ Recovery: Connect to device  │
│ Advantage: Air-gap safe,     │
│           no network risk    │
└──────────────────────────────┘
```

**Comparison Table**:
| Tier | Security | Access Time | Recovery | Longevity | Cost | Use Case |
|------|----------|-------------|----------|-----------|------|----------|
| 1. Keychain | High (TEE) | <1ms | File import | Until iOS update | Free | Primary |
| 2. iCloud | High (E2E) | 100ms+ | Auto-restore | With Apple | Free | Backup |
| 3. File | Medium | File I/O | Manual | Indefinite | Variable | Cold storage |
| 4. USB-C | Very High | USB I/O | Manual | 10+ years | $$$$ | Ultimate backup |

---

### 5. Backup & Recovery Strategies (`backup-recovery-strategies.html`)

**Why**: Map backup approaches to custody models and recovery scenarios

**Strategy Matrix**:

| Strategy | Best For | Procedure | Recovery | Risk |
|----------|----------|-----------|----------|------|
| **No Backup** | Dev, throwaway keys | Generate key, use, delete | Key is lost | Total loss if damage |
| **iCloud Only** | Single device user | Enable iCloud Backup (system-wide) | Restore from iCloud | Depends on Apple security |
| **File Export** | Cold storage, paranoid users | Export to encrypted file, store offline | Import file + passphrase | Passphrase guessing, file loss |
| **USB-C Backup** | Long-term custody, air-gap | Export to USB device (PIN-locked) | Connect USB, restore | USB device loss/damage |
| **2-of-2 w/ File Backup** | 2-party custody | Each device exports its share as file | Device lost? Recover from file | Files must be stored separately |
| **2-of-3 Threshold** | Enterprise | Server backup + device backup | Any 2 of 3 can refresh | None (3-way redundancy) |

**Recovery Procedures**:

#### Scenario 1: Single Device Lost (No Backup)
- Outcome: Key is permanently lost
- Next: Generate new key

#### Scenario 2: Single Device Lost (iCloud Backup)
- Outcome: Restore to new device from iCloud backup
- Procedure: Install app → Sign in with Apple ID → Restore keys → Done

#### Scenario 3: 2-of-2 Device Lost (File Backup)
- Outcome: Import from backup file on remaining device
- Procedure:
  1. On Device B: "Restore Key Share"
  2. Select encrypted backup file from Files/email/cloud
  3. Enter passphrase
  4. Device B now has both Share 0 and Share 1 (can sign alone)

#### Scenario 4: 2-of-3 Threshold (Device Lost)
- Outcome: Use remaining 2 parties (Device A + Server)
- Procedure:
  1. Lost Device C
  2. Initiate "Threshold Refresh"
  3. Quorum of 2 (Device A + Server) runs refresh protocol
  4. New Share 3 generated for replacement device
  5. Old Device C's share automatically invalidated

---

## "Create New Key" Progressive Disclosure UI

**Goal**: Guide users to right custody model without overwhelming them

**Phase 1: Initial Choice (What security model?)**

```
┌─────────────────────────────────────┐
│  Create New Key                     │
├─────────────────────────────────────┤
│                                     │
│  How do you want to secure this key?│
│                                     │
│  ☑ Just me (one device)            │  [RECOMMENDED - checked by default]
│    → Fastest, simplest              │  [Icon: phone]
│    → Good for testing & personal    │
│    → Can export for backup          │
│                                     │
│  ○ Me + trusted partner (2 devices) │  [ICON: phone + phone]
│    [See details]                    │  [GREYED: More complex, slower]
│                                     │
│  ○ Enterprise (server backup)       │  [ICON: phone + cloud]
│    [See details]                    │  [GREYED: Needs infrastructure]
│                                     │
│            [Next] [Cancel]          │
└─────────────────────────────────────┘
```

**Phase 2: For 2-Device Option (How to connect?)**

```
┌──────────────────────────────────────────┐
│  Create with Trusted Partner             │
├──────────────────────────────────────────┤
│                                          │
│  How will you exchange the key share?   │
│                                          │
│  ☑ Bluetooth (if nearby)                │  [RECOMMENDED - fastest]
│    → Real-time protocol                  │  [Icon: bluetooth]
│    → Requires second device with app     │  [SUB-TEXT: ~2 min, live]
│    → Device must be present              │
│                                          │
│  ○ QR Code (any time)                   │  [Icon: QR code]
│    → Air-gap safe, offline              │  [SUB-TEXT: ~5 min, no internet]
│    → Can do later                        │
│    → Works across continents             │
│                                          │
│         [Next] [Cancel] [Back]          │
└──────────────────────────────────────────┘
```

**Phase 3: For Enterprise (Server Integration)**

```
┌──────────────────────────────────────────┐
│  Enterprise Setup (2-of-3 Threshold)     │
├──────────────────────────────────────────┤
│                                          │
│  Server URL: [________________]          │
│  [Help - How to set up server?]         │
│                                          │
│  Second Device to Pair:                  │
│  ☑ Another iPhone                        │  [SUB: Nearby via BLE]
│  ○ Someone else's iPhone                 │  [GREYED: Future feature]
│                                          │
│  Policy Settings:                        │
│  [⚙] Configure rate limits               │
│  [⚙] Require approval for large txn      │
│  [⚙] Whitelist addresses                 │
│                                          │
│           [Create Key] [Cancel] [Back]  │
└──────────────────────────────────────────┘
```

**Key UX Principles**:
- Recommended option (1-device) is checked by default
- Other options greyed out with explanation text
- "See details" links expand explanations inline
- Sub-sheets for advanced options (policy, server config)
- Clear next/back navigation
- Each phase shows what's coming next

---

## Storage & Backup Priority Hierarchy

**Order of storage targets** (user selects combination):
1. **Keychain** (primary, on device)
2. **iCloud Keychain** (backup, synced across user's devices)
3. **Another Device** (via BLE, for multi-device setup)
4. **USB-C File** (encrypted, password/biometric-protected, air-gap safe)
5. **Server** (policy enforcement, audit, redundancy)
6. **QR Code** (air-gapped transfer only, NOT for signing operations)

---

## 2-Party / 3-Party / N-Party Permutations (Default: 2-Party Device + Server)

### Default Configuration: 2-Party with Server Backup

```
┌──────────────────┐                    ┌──────────────┐
│ User's iPhone    │                    │ Signing      │
│ ┌──────────────┐ │  Signing Protocol  │ Server       │
│ │ Share 0      │ │←────────────────→  │ ┌──────────┐ │
│ │ (Keychain)   │ │  (2-of-2 signing)  │ │Share 1   │ │
│ │              │ │                    │ │(HSM/safe)│ │
│ │ BACKUP:      │ │                    │ └──────────┘ │
│ │ iCloud or    │ │                    │              │
│ │ USB-C        │ │                    │ BACKUP:      │
│ └──────────────┘ │                    │ USB-C file   │
└──────────────────┘                    └──────────────┘
```

- **Setup**: 2-party DKG on device, share 1 stored on server
- **Signing**: iPhone + Server both participate (real-time via network)
- **Security**: Neither device nor server alone can sign
- **Backups**:
  - iPhone: Share 0 in Keychain + iCloud Keychain backup
  - Server: Share 1 backed up to USB-C encrypted file
- **Cost**: Free (device) + server infrastructure
- **Use Case**: Default for all users

---

### 2-Party Variants

#### 2-Party Variant A: Device + Device (BLE)
```
Device A (iPhone)           Device B (iPhone)
├─ Share 0 (Keychain)  ←BLE→  ├─ Share 1 (Keychain)
│  Backup: USB-C or          │  Backup: USB-C or
│           iCloud           │           iCloud
```

- **Setup**: Both devices run 2-party DKG via BLE (phones must be together)
- **Signing**: Both devices online, BLE coordination
- **Security**: Each device holds 1 share, shares never meet
- **Backups**: Each device exports its share to USB-C file or iCloud
- **Use Case**: Co-custody (married couple, business partners), offline-capable
- **Advantage**: No server needed, air-gap option via QR code

#### 2-Party Variant B: Device + USB-C File (Hybrid)
```
Device (iPhone)              USB-C Key
├─ Share 0 (Keychain)   +    ├─ Share 1 (encrypted file)
│  Backup: USB-C or         │  Password + biometric
│           iCloud          │  (physical key needed)
```

- **Setup**: Share 0 on device, Share 1 on USB-C file (encrypted with passphrase/FaceID)
- **Signing**: Need both iPhone + USB-C key (physically plug in)
- **Security**: Share 0 on device, Share 1 on removable hardware
- **Backups**: iPhone backed up to iCloud; USB-C file UUID-locked to prevent cloning
- **Use Case**: Maximum security, physical key custody
- **Advantage**: USB-C key can't sign alone; can create second USB-C backup

#### 2-Party Variant C: Device + Device + Server (fallback)
```
Device A (iPhone)      Device B (iPhone)      Server
├─ Share 0 (KC)  ←BLE→ ├─ Share 1 (KC)
│                       │
Backup: iCloud/USB      Backup: iCloud/USB    Share 0 or 1 backed up
                                               (policy enforcement)
```

- **Setup**: 2 devices sync via BLE, server stores backup share
- **Signing**: Requires Device A + Device B (server only for recovery)
- **Use Case**: Family co-custody with enterprise backup
- **Advantage**: 2-of-2 for daily signing, server provides audit trail

---

### 3-Party Variants

#### 3-Party Variant A: Device + iCloud + Server (Default Upgrade)
```
Device (iPhone)         iCloud Keychain         Server
├─ Share 0 (KC)    +    ├─ Share 0 Backup       ├─ Share 1
│ Backup: USB-C        │ (synced)              │ Backup: USB-C
```

- **Setup**: Share 0 on device + iCloud, Share 1 on server
- **Threshold**: 2-of-3 (device + iCloud alone can't sign; device + server can)
- **Signing**: Device + Server (iCloud is backup only)
- **Use Case**: Default for users who want server policy enforcement + redundancy
- **Advantage**: If device lost, iCloud + Server can refresh to new device

#### 3-Party Variant B: Device A + Device B + Server (2-Device + Server)
```
Device A (iPhone)    Device B (iPhone)    Server
├─ Share 0 (KC)  +   ├─ Share 1 (KC)      ├─ Share 2
│ Backup: USB-C      │ Backup: USB-C      │ Backup: USB-C
└─ iCloud backup     └─ iCloud backup     │
```

- **Setup**: Each device holds 1 share, server holds share 2, all have USB-C backups
- **Threshold**: 2-of-3 (any 2 parties can sign)
- **Signing**: Device A + Device B (most common), or Device A + Server, or Device B + Server
- **Use Case**: Co-custody with server-based policy enforcement
- **Advantage**: One device lost = remaining device + server can refresh

#### 3-Party Variant C: Device + iCloud + USB-C (No Server)
```
Device (iPhone)         iCloud Keychain      USB-C File
├─ Share 0 (KC)    +    ├─ Share 0 Backup     ├─ Share 1 (encrypted)
│ (signing ops)         │ (recovery)          │ (physical backup)
```

- **Setup**: Share 0 on device, Share 1 on USB-C file, iCloud backs up both
- **Threshold**: 2-of-3 (device + iCloud, or device + USB-C)
- **Signing**: Device alone (iCloud/USB-C as backups)
- **Use Case**: Personal custody, no server required
- **Advantage**: Air-gap safe, can operate offline

---

### N-Party Variants: Family/Friends Sharing

#### N-Party Variant A: 3-of-5 Default (Device + Device + Device + iCloud + USB-C)
```
Your iPhone        Friend A iPhone      Friend B iPhone     iCloud    USB-C
├─ Share 1 (KC) +  ├─ Share 2 (KC)   +  ├─ Share 3 (KC)   + Backup + Backup
```

- **Setup**: You + 2 friends (each holds share), iCloud syncs all, USB-C backup
- **Threshold**: 3-of-5 (need 3 of: your device, friend A, friend B, iCloud, USB-C)
- **Signing**: 3 devices + iCloud, or 2 devices + USB-C + iCloud, etc.
- **Use Case**: Family treasury, shared key for joint account
- **Setup Flow**:
  1. You initiate on your device
  2. Friend A joins via BLE (scans code or sits nearby)
  3. Share 1 transferred to Friend A's device via BLE
  4. Friend B joins via BLE
  5. Share 2 transferred to Friend B's device via BLE
  6. All 3 devices synced to iCloud Keychain
  7. USB-C backup created for physical recovery

#### N-Party Variant B: 3-of-5 with QR (Air-Gap Transfer)
```
Your iPhone        Friend A iPhone      Friend B iPhone
├─ Share 1 (KC) +  ├─ Share 1 (from QR)  ├─ Share 1 (from QR)
                   └─ + USB-C file       └─ + USB-C file
```

- **Setup**: You export via QR code (offline), friends scan and import
- **Advantage**: Air-gap safe, friends don't need to be present
- **Flow**:
  1. You generate key on your device
  2. Export Share 1 as QR code (multi-part sequence)
  3. Email QR code to Friend A (or display on screen)
  4. Friend A scans QR, imports to their device
  5. Friend B scans QR, imports to their device
  6. All synced to iCloud Keychain

#### N-Party Variant C: Governance (3-of-5 Admins, Enterprise)
```
Admin 1 (Device) + Admin 2 (Device) + Admin 3 (Device) + Admin 4 (Device) + Admin 5 (Device)
Each has Share 1, 2, 3, 4, 5
Threshold: 3-of-5
```

- **Setup**: Via server coordination (WebSocket + mTLS)
- **Signing**: Requires quorum of 3
- **Use Case**: DAO treasury, corporate board approval
- **Advantage**: Decentralized approval, can add/remove admins

---

### Permutation Build Priority

**Do not implement all at once. This is the recommended learning order:**

| Priority | Variant | Core Tech | Dependencies | Est. Effort | Unlock Next |
|----------|---------|-----------|--------------|-------------|-------------|
| **1** | 2-Party: Device + Server (default) | DKG, signing, iOS keychain, server API | HTTP/WebSocket, basic auth | HIGH | Multi-device |
| **2** | 2-Party: Device + Device (BLE) | DKG, BLE pairing, mTLS certs | Priority 1 + BLE stack | HIGH | Family sharing |
| **3** | 2-Party: Device + USB-C | DKG, file export, passphrase encryption | Priority 1 + file I/O | MEDIUM | Recovery flows |
| **4** | 3-Party: Device + iCloud + Server | Threshold DKG, threshold signing, iCloud backup | Priority 1 + iCloud API | MEDIUM | Advanced backups |
| **5** | 3-Party: 2 Devices + Server | Multi-device DKG, threshold refresh | Priority 1 + 2 | MEDIUM | Family treasury |
| **6** | N-Party: 3-of-5 Family (BLE) | Family sharing via BLE, progressive disclosure | Priority 2 + 5 | HIGH | Enterprise |
| **7** | N-Party: QR Air-Gap Transfer | QR export/import, offline distribution | Priority 3 + QR codec | MEDIUM | Governance |
| **8** | N-Party: 3-of-5 Enterprise | WebSocket coordination, policy API, audit logs | Priority 6 + server upgrade | HIGH | DAO/VC |

---

## Default User Experience

### User Question 1: "What type of key?"
- Single private key (import/legacy)
- **Default: 2-Party Distributed Key** (2 shares, you hold 1, server holds 1)

### User Question 2: "How many parties/backups?"
- **Default: 2-Party + iCloud + USB-C backup**
  - Sharing scenario: Upgrade to 3-of-5 with family members
  - Enterprise scenario: Switch to 3-of-5 governance later

### User Question 3 (if 2-Party): "How to coordinate signing?"
- **Default: Network + Server** (always online)
- Advanced: Switch to Device + Device (BLE) for co-custody
- Advanced: Switch to Device + USB-C (physical key)

### User Question 4 (if N-Party): "Add parties how?"
- **Default: Nearby via BLE** (sit together, scan code)
- Alternative: QR code (air-gap, email-friendly)
- Alternative: USB-C file (portable backup)

---

## Visual Guide Pages Summary

| Page | Purpose | Content | Wireframes |
|------|---------|---------|-----------|
| QR Transfer | How keys move via QR | Encryption, framing, scanning, decryption | Device A export → Device B import |
| Bluetooth | Real-time pairing | BLE discovery, certs, mTLS, protocol rounds | Pairing UI → connected state → protocol progress |
| Custody Models | Choose security model | 4 models with security/availability/cost analysis | Model diagrams + comparison table |
| Storage Hierarchy | Where to store shares | 4 tiers with security/performance analysis | Tier comparison table |
| Backup & Recovery | How to recover from loss | 5 strategies + 4 recovery scenarios | Recovery flowcharts + decision tree |

---

## Next Steps

1. **Review & Refine**: Validate storage hierarchy (Keychain/iCloud/USB-C correct?)
2. **Wireframe Feedback**: Do progressive disclosure patterns match your vision?
3. **Permutation Prioritization**: Which 2-party variant to document first? (2a-QR likely)
4. **Document Then Sit**: Complete wireframes, iterate, then decide build sequence

---

**Status**: Documentation & planning phase. No HTML pages created yet.
**Deliverable**: Comprehensive wireframes + permutation matrix before implementation.
