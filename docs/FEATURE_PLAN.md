# CB-MPC iOS Feature Plan

## Overview

Transform the current demo/prototype into a production-quality MPC vault app by implementing the workflows shown in the [visual guide](https://cb-mpc-visual-guide.atsignhandle.workers.dev), adding real-world features (USB backup, device-to-device comms, commitment server), integrating tutorial flows, and applying a neo-brutalist + terminal design system.

---

## Design System: Terminal Neo-Brutalist

A hybrid of monospace terminal aesthetics, iOS platform conventions, and neo-brutalist design.

### Typography

| Role | Font | Size | Weight |
|------|------|------|--------|
| H1 / Screen Title | SF Mono | 20pt | 900 (Black) |
| H2 / Section | SF Mono | 16pt | 700 (Bold) |
| Body | SF Mono | 13pt | 400 |
| Caption / Labels | SF Mono | 10pt | 500 (Medium) |
| Crypto Data (keys, hashes, sigs) | SF Mono | 11pt | 400 |
| Status Badges | SF Mono | 9pt | 700, ALL CAPS |

### Colors

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `--bg` | `#FAFAF9` | `#0C0C0C` | Page background |
| `--surface` | `#FFFFFF` | `#1A1A1A` | Card backgrounds |
| `--border` | `#000000` | `#3A3A3A` | 2-3px hard borders |
| `--text` | `#1A1A1A` | `#E5E5E5` | Primary text |
| `--accent-indigo` | `#6366F1` | `#818CF8` | Primary actions, Party 0 |
| `--accent-amber` | `#F59E0B` | `#FBBF24` | Party 1 / Server |
| `--accent-emerald` | `#10B981` | `#34D399` | Success, verified |
| `--accent-red` | `#EF4444` | `#F87171` | Danger, invalid |
| `--secret` | `#EF4444` | `#F87171` | Secret data tags |
| `--public` | `#3B82F6` | `#60A5FA` | Public data tags |

### Component Patterns

- **Cards**: 2-3px solid black border, no rounded corners (0 radius), 12px padding
- **Buttons**: Solid fill, 3px box-shadow offset (bottom-right), ALL CAPS labels, no border-radius
- **Status Badges**: `[OK]`, `[FAIL]`, `[...]` in monospace, colored background pills
- **Progress**: Terminal-style `[1/3] Step name.......[DONE]`
- **Inputs**: Monospace, thin border, no rounded corners, cursor-blink animation on focus
- **Dividers**: Solid 1px lines or `────────────` text dividers
- **Icons**: Minimal SF Symbols, prefer text symbols (*, >, |, #)

### Layout

- 12px page padding (matches current)
- 8px card internal padding
- Hard edges everywhere (cornerRadius: 0)
- Full-width buttons for primary actions
- Left-aligned text, no center alignment except modals

---

## Phase 1: Core Vault Workflows

Implement the primary screens from the visual guide as real, functional workflows.

### 1.1 Welcome / Onboarding

**New file**: `Views/WelcomeView.swift`

- Full-screen onboarding shown on first launch (no keys in store)
- Header: `CB-MPC Vault` with key symbol
- Tagline: "Threshold key management. Your key never exists in one place."
- Two CTAs: `CREATE NEW VAULT` | `RESTORE FROM BACKUP`
- Replace current auto-seed behavior with this screen
- Store `hasCompletedOnboarding` in UserDefaults

### 1.2 Key Share Generation Flow

**New file**: `Views/KeyGenFlowView.swift`

Multi-step generation view replacing the current simple CreateKeySheetView modal:

1. **Configure step**: Key name, type selection (Simple / HD Master / HD Child), curve selection
2. **Generating step**: Live progress display
   - Protocol: "ECDSA-2PC KeyGen (secp256k1)"
   - Round status: "Round 1/3: Generating commitments..." → "Round 2/3: Exchanging..." → "Round 3/3: Finalizing..."
   - Progress bar
   - Security notice about Secure Enclave storage
3. **Complete step**: Show generated public key, key share metadata, party roles
   - CTA: `BACKUP KEY SHARE` | `SKIP FOR NOW`

### 1.3 Transaction Signing Flow

**Modify**: `Views/SignMessageSheetView.swift`

Redesign to match visual guide's multi-phase signing:

1. **Request screen**: Show message/tx details, hash, protocol info, `APPROVE & SIGN` | `REJECT`
2. **Progress screen**: Terminal-style phase tracking
   - `[1/3] Nonce commitment [DONE]`
   - `[2/3] Partial signature [DONE]`
   - `[3/3] Signature assembly [...]`
   - Explanation text about partial computation
3. **Complete screen**: Signature display, verification badge `[OK] SIGNATURE VERIFIED`, copy/broadcast buttons

### 1.4 Key Refresh

**New file**: `Views/KeyRefreshView.swift`

- Show current key state (PK, share, last refresh, refresh count)
- Preview post-refresh state (PK same, share new, old destroyed)
- Explanation of forward security
- `START REFRESH PROTOCOL` button
- Progress display during refresh
- Completion confirmation

### 1.5 Vault Dashboard Redesign

**Modify**: `Views/KeyDashboardView.swift`

Replace flat key list with visual guide's dashboard layout:

- Active vault card: name, curve, mode, status badge
- Public key display with QR
- Key share health indicators: Secure Enclave status, last refresh, backup status, counterparty status
- Primary CTAs: `SIGN TX` | `REFRESH` | `BACKUP`
- Secondary: `HISTORY`

---

## Phase 2: Backup & Restore

### 2.1 Backup to USB-C

**New files**: `Views/BackupFlowView.swift`, `Models/USBBackupManager.swift`

**Backup setup screen**:
- Title: "Backup Key Share"
- Method selection: USB-C Drive | iCloud Keychain
- Access structure display (tree visualization)

**USB-C flow**:
- Drive detection using `UIDocumentPickerViewController` or External Accessory framework
- Display drive info (name, capacity, available space)
- Backup contents table showing files to write:
  - `vault-backup/encrypted_share.pve` [SECRET]
  - `vault-backup/public_key.json` [PUBLIC]
  - `vault-backup/access_structure.json` [PUBLIC]
  - `vault-backup/verification_proof.bin` [PUBLIC]
  - `vault-backup/metadata.json` [PUBLIC]
- Write operation with progress
- Verification screen: checkmarks for AES-256-GCM, RSA-2048 OAEP, ZK proof, SHA-256 integrity
- Size summary

**Implementation**: Encrypt key share with AES-256-GCM, wrap key with device-bound key, write to user-selected directory via document picker. On iOS, USB-C drives appear as document providers.

### 2.2 Restore from USB-C

**New file**: `Views/RestoreFlowView.swift`

1. **Connect screen**: Prompt for USB-C drive, show prerequisites
2. **Load screen**: Parse backup directory, validate files
3. **Quorum collection** (if access structure requires it):
   - Show required contacts
   - Track partial decryptions received
   - Status badges per contact
4. **Restore**: Aggregate partial decryptions, recover key share
5. **Verification**: Confirm x_i matches original, Q_i = x_i * G, public key unchanged
6. **Complete**: Store in Secure Enclave, offer key refresh

### 2.3 iCloud Keychain Backup

**New file**: `Models/iCloudBackupManager.swift`

- Encrypt key share with device-derived key
- Store in iCloud Keychain using `kSecAttrSynchronizable`
- Restore via Keychain query on new device
- Sync status indicator in dashboard

---

## Phase 3: Signature Touch Copy

### 3.1 Quick Copy Actions

**Modify**: `Views/SignMessageSheetView.swift`, `Views/KeyDetailView.swift`

- After signing, show signature with large tap target
- Single tap → copy signature hex to clipboard with haptic feedback
- Toast notification: "Signature copied"
- Long press → share sheet (AirDrop, Messages, etc.)
- Copy button for public key with same haptic pattern

### 3.2 Signature QR Code

- Generate QR code for signature output (already have QRCodeView)
- Allow scanning QR to import signatures for verification
- Add camera-based QR scanner in VerifySignatureSheetView for pasting external signatures

---

## Phase 4: Commitment Server

### 4.1 Server Communication

**New files**: `Models/CommitmentServerClient.swift`, `Views/ServerStatusView.swift`

The commitment server acts as the second MPC party (Party 1) for real 2-party operations.

**Client implementation**:
- WebSocket connection to commitment server
- REST API for session management
- Endpoints: `/keygen/init`, `/keygen/round/{n}`, `/sign/init`, `/sign/round/{n}`, `/refresh`, `/status`
- TLS certificate pinning
- Reconnection with exponential backoff

**Server status view**:
- Connection indicator (green/red dot)
- Latency display
- Server version/capabilities
- Last heartbeat timestamp

### 4.2 Remote Key Generation

Replace local 2-party simulation with real server-backed DKG:
- Client sends commitment to server
- Server responds with its commitment
- Exchange continues through rounds
- Client stores Party 0 share, server stores Party 1 share

### 4.3 Remote Signing

- Client initiates signing request to server
- Multi-round protocol execution over WebSocket
- Neither party sees full private key
- Client receives final signature

---

## Phase 5: Device-to-Device Communication

### 5.1 Multipeer Connectivity

**New files**: `Models/PeerTransport.swift`, `Views/PeerConnectionView.swift`

Use Apple's MultipeerConnectivity framework (already have Bonjour service `_cbmpc._tcp` in Info.plist):

- Browse for nearby peers
- Invite/accept connections
- Exchange MPC protocol messages over peer session
- Support for 2-party and N-party configurations

**Peer connection screen**:
- Device discovery list with signal strength
- Invite/accept UI
- Connection status per peer
- Role assignment (Party 0, Party 1, ...)

### 5.2 Cross-Device Key Generation

- Two (or N) devices run DKG protocol over MultipeerConnectivity
- Each device stores its own key share
- Public key displayed on all devices for verification
- No server required -- pure peer-to-peer MPC

### 5.3 Cross-Device Signing

- Initiating device broadcasts sign request
- All parties participate in signing protocol
- Final signature assembled and distributed
- Audit log on all devices

### 5.4 QR Code Pairing Fallback

For devices not on same network:
- Generate pairing QR code with session ID + relay server URL
- Scan to establish connection via relay
- WebRTC data channel for protocol messages

---

## Phase 6: Demo Workflow Integration

Transform existing demo views from isolated tests into guided, interactive workflows accessible from the main app.

### 6.1 Demo Runner Redesign

**Modify**: `Views/DemoHubView.swift`, `Views/DemoShared.swift`

Current demos run automatically and display results. Redesign to:
- Step-by-step walkthroughs with "Next" button between steps
- Explanatory text for each protocol phase
- Visual state diagrams showing data flow between parties
- Option to auto-run (current behavior) or step-through

### 6.2 Demo-to-Feature Bridge

Each demo should link to the real feature when available:

| Demo | Links To |
|------|----------|
| CryptoDemoView (ECDSA 2P) | Key Generation + Signing flow |
| ECDSAMPDemoView (N-Party) | Device-to-Device multi-party |
| EdDSADemoView | EdDSA key creation (future) |
| HDDerivationDemoView | HD Master/Child key creation |
| BatchSigningDemoView | Batch signing mode in sign sheet |
| KeyLifecycleDemoView | Key Refresh flow |
| NPartyDemoView (Backup) | USB-C Backup & Restore |
| AgreeRandomDemoView | Secure randomness (nonce generation) |
| AccessStructureDemoView | Backup access policies |
| ZKProofDemoView | Verification proofs display |

### 6.3 Interactive Tutorials

**New file**: `Views/TutorialView.swift`, `Models/TutorialManager.swift`

Overlay tutorial system that guides users through real app features:

1. **"Your First Key"** -- Walk through key generation, explain what's happening cryptographically
2. **"Sign a Message"** -- Guide through signing flow, explain nonce, hash, DER format
3. **"Verify a Signature"** -- Show verification, explain ECDSA math at high level
4. **"Backup Your Vault"** -- Walk through USB-C or iCloud backup
5. **"HD Key Derivation"** -- Explain BIP-32/BIP-44, derive child keys
6. **"Key Refresh"** -- Explain forward security, run refresh
7. **"Multi-Party Signing"** -- Connect devices, run N-party protocol

Each tutorial:
- Highlight UI elements with spotlight overlay
- Show explanatory callouts with monospace text
- Track completion in UserDefaults
- Accessible from Settings > Tutorials

---

## Phase 7: Screen Implementation from Visual Guide

Map every visual guide screen to implementation:

| Visual Guide Screen | Status | Implementation |
|---------------------|--------|----------------|
| Welcome / Onboarding | New | Phase 1.1 |
| Key Share Generation (in-progress) | New | Phase 1.2 |
| Key Share Generation (complete) | Partial | Enhance CreateKeySheetView |
| Transaction Signing (request) | Partial | Phase 1.3 |
| Transaction Signing (in-progress) | New | Phase 1.3 |
| Transaction Signing (complete) | Partial | Phase 1.3 |
| Backup Setup | New | Phase 2.1 |
| USB-C Connected | New | Phase 2.1 |
| Backup Verification | New | Phase 2.1 |
| Restore Init | New | Phase 2.2 |
| Quorum Collection | New | Phase 2.2 |
| Restore Complete | New | Phase 2.2 |
| Key Refresh | New | Phase 1.4 |
| Vault Dashboard | Partial | Phase 1.5 |

---

## Phase 8: Polish & App Store Readiness

### 8.1 Design System Implementation

**New file**: `Views/DesignSystem.swift`

Centralized style definitions:

```swift
struct CBStyle {
    static let borderWidth: CGFloat = 2
    static let shadowOffset: CGFloat = 3
    static let cardPadding: CGFloat = 12
    static let pagePadding: CGFloat = 12
    static let cornerRadius: CGFloat = 0

    struct Fonts {
        static let h1 = Font.system(size: 20, weight: .black, design: .monospaced)
        static let h2 = Font.system(size: 16, weight: .bold, design: .monospaced)
        static let body = Font.system(size: 13, weight: .regular, design: .monospaced)
        static let caption = Font.system(size: 10, weight: .medium, design: .monospaced)
        static let crypto = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let badge = Font.system(size: 9, weight: .bold, design: .monospaced)
    }

    struct Colors {
        static let indigo = Color(hex: "#6366F1")
        static let amber = Color(hex: "#F59E0B")
        static let emerald = Color(hex: "#10B981")
        static let danger = Color(hex: "#EF4444")
    }
}
```

### 8.2 View Modifiers

```swift
struct BrutalistCard: ViewModifier { ... }     // 2px border, 0 radius, shadow
struct BrutalistButton: ButtonStyle { ... }    // Solid fill, shadow offset, caps
struct StatusBadge: View { ... }               // [OK] / [FAIL] / [...] pills
struct TerminalProgress: View { ... }          // [1/3] Step......[DONE]
struct CryptoDataView: View { ... }            // Monospace hex with copy
```

### 8.3 Haptics

- Light impact on button press
- Medium impact on successful sign/verify
- Success notification on key generation complete
- Error notification on verification failure

### 8.4 Accessibility

- VoiceOver labels for all crypto data
- Dynamic Type support (minimum sizes for crypto data)
- Reduce Motion support (skip animations)

---

## Implementation Priority

| Priority | Phase | Effort | Impact |
|----------|-------|--------|--------|
| 1 | 8.1 Design System | 1 week | Foundation for everything |
| 2 | 1.1 Welcome | 2 days | First impression |
| 3 | 1.2 KeyGen Flow | 3 days | Core workflow |
| 4 | 1.3 Signing Flow | 3 days | Core workflow |
| 5 | 3.1 Touch Copy | 1 day | Quick win, UX improvement |
| 6 | 1.4 Key Refresh | 2 days | Already have crypto |
| 7 | 1.5 Dashboard | 3 days | Main screen redesign |
| 8 | 6.3 Tutorials | 1 week | User education |
| 9 | 6.1-6.2 Demo Redesign | 1 week | Bridge demos to features |
| 10 | 2.1 USB Backup | 1 week | Critical feature |
| 11 | 2.2 USB Restore | 1 week | Critical feature |
| 12 | 4.1-4.3 Commitment Server | 2 weeks | Real MPC operations |
| 13 | 5.1-5.3 Device-to-Device | 2 weeks | Peer-to-peer MPC |
| 14 | 2.3 iCloud Backup | 3 days | Convenience backup |
| 15 | 8.2-8.4 Polish | 1 week | App Store readiness |

---

## Repository Structure

```
cb-mpc/
  CBMPCNative/              -- iOS app (SwiftUI + C++ FFI)
  server/                   -- Commitment server (Party 1)
    src/
      index.ts              -- Entry point
      mpc/
        keygen.ts           -- DKG protocol handler
        sign.ts             -- Signing protocol handler
        refresh.ts          -- Key refresh handler
      transport/
        websocket.ts        -- WebSocket session management
      storage/
        keyshare.ts         -- Server-side key share persistence
    package.json
    tsconfig.json
  docs/                     -- Visual guides, feature plan
  src/                      -- C++ MPC library (shared by both)
```

The server runs as Party 1 in the 2-party MPC protocol. It holds its own key share and participates in keygen/signing rounds. The iOS app (Party 0) connects via WebSocket.

**Tech stack**: Bun/TypeScript, WebSocket for protocol rounds, SQLite or KV for key share storage. Can deploy to Cloudflare Workers with Durable Objects later if needed.

---

## Files to Create

```
Views/
  DesignSystem.swift          -- Style constants, view modifiers, reusable components
  WelcomeView.swift           -- Onboarding screen
  KeyGenFlowView.swift        -- Multi-step key generation
  KeyRefreshView.swift        -- Key refresh workflow
  BackupFlowView.swift        -- Backup setup + USB-C + verification
  RestoreFlowView.swift       -- Restore from backup + quorum
  ServerStatusView.swift      -- Commitment server connection
  PeerConnectionView.swift    -- Device-to-device discovery
  TutorialView.swift          -- Tutorial overlay system

Models/
  USBBackupManager.swift      -- USB-C file operations + encryption
  iCloudBackupManager.swift   -- iCloud Keychain backup
  CommitmentServerClient.swift -- WebSocket/REST server client
  PeerTransport.swift         -- MultipeerConnectivity wrapper
  TutorialManager.swift       -- Tutorial state tracking
```

## Files to Modify

```
Views/
  KeyDashboardView.swift      -- Dashboard redesign
  SignMessageSheetView.swift   -- Multi-phase signing UI
  CreateKeySheetView.swift    -- Link to KeyGenFlowView
  DemoHubView.swift           -- Step-through mode, feature links
  DemoShared.swift            -- Interactive step components
  FloatingTabBar.swift        -- Neo-brutalist styling
  SettingsView.swift          -- Add tutorials, server config
  AppNavigation.swift         -- Add welcome screen gate

Models/
  KeyStore.swift              -- Server-backed operations
```


Human Notes:

- [ ] https://expo.dev/blog/universal-and-app-links?utm_campaign=13932868-Sign%20up%20Nurture%20Program&utm_medium=email&_hsenc=p2ANqtz-99z7kLGs7WbuO_7IN_3JCckFOS9eG0U4QuRi3WNOoPSdnLSd0qXOOdp14hXC_Mlv4z2P6tlMrcqYV4dfkBn5ZLyOS483KEZC1HugGzA1g78FzPWwc&_hsmi=381783995&utm_content=381783995&utm_source=hs_automation 
