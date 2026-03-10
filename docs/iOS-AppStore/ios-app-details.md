# iOS App Store Connect Details — TestFlight Submission

Reference for filling out App Store Connect fields. Sections map to the ASC sidebar.

## Programmatic Upload

All metadata can be uploaded via the App Store Connect REST API. See `scripts/asc-metadata.sh`.

### Setup

1. Create an API key at [App Store Connect > Integrations](https://appstoreconnect.apple.com/access/integrations/api)
2. Download the `.p8` private key file
3. Export env vars:

```bash
export ASC_KEY_ID="your-key-id"
export ASC_ISSUER_ID="your-issuer-id"
export ASC_KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_XXXXX.p8"
```

### Commands

```bash
./scripts/asc-metadata.sh info         # Fetch current app info + IDs
./scripts/asc-metadata.sh upload       # Push metadata from fastlane/metadata/
./scripts/asc-metadata.sh age-rating   # Set all age ratings to NONE
./scripts/asc-metadata.sh review       # Set App Review contact info
./scripts/asc-metadata.sh testflight   # Set "What to Test" on latest build
./scripts/asc-metadata.sh all          # Run upload + age-rating + review
```

### Metadata Files

All values live in `fastlane/metadata/` (fastlane-compatible layout):

```
fastlane/metadata/
  copyright.txt
  primary_category.txt        → UTILITIES
  secondary_category.txt      → FINANCE
  age_rating_config.json      → all NONE
  en-US/
    name.txt                  → Key MGMT wCB-MPC
    subtitle.txt              → Threshold Key Management
    description.txt           → Full App Store description
    keywords.txt              → mpc,threshold,crypto,...
    promotional_text.txt      → Short promo line
    release_notes.txt         → What's New / What to Test
    privacy_url.txt           → Worker /privacy route
    support_url.txt           → GitHub repo
  review_information/
    first_name.txt            → Mark
    last_name.txt             → Phillips
    phone_number.txt          → 760-507-7572
    email_address.txt         → roooot@atsignhandle.xyz
    notes.txt                 → Reviewer instructions
```

### Privacy Policy

Hosted at the key server worker:
- HTML: `https://cb-mpc-key-server.atsignhandle.workers.dev/privacy`
- JSON: `https://cb-mpc-key-server.atsignhandle.workers.dev/privacy.json`

---

## Localizable Information

| Field | Value |
|-------|-------|
| **Name** | Key MGMT wCB-MPC |
| **Subtitle** (30 chars max) | Threshold Key Management |

---

## General Information

| Field | Value |
|-------|-------|
| **Bundle ID** | `xyz.atsignhandle.cb-mpc` |
| **SKU** | `0000002` |
| **Apple ID** | `6760239004` |
| **Primary Language** | English (U.S.) |
| **Primary Category** | Utilities |
| **Secondary Category** | Finance (optional) |

---

## Content Rights

- Does your app contain, show, or access third-party content? **No**
- License Agreement: **Apple's Standard License Agreement** (default)

---

## Age Ratings

Answer "None" to all questions except:

| Question | Answer |
|----------|--------|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Profanity or Crude Humor | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Simulated Gambling | None |
| Unrestricted Web Access | None |
| Gambling and Contests | None |

**Result:** Rated 4+ (no objectionable content)

---

## App Privacy (Privacy Nutrition Labels)

### Data Collection

The app does **not** collect data that is linked to user identity. Declare the following:

| Data Type | Collection | Linked to Identity | Tracking |
|-----------|------------|-------------------|----------|
| None | No data collected | N/A | No |

**Privacy Policy URL** (required): `https://cb-mpc-key-server.atsignhandle.workers.dev/privacy`

> Policy text (hosted at the URL above): "Key MGMT wCB-MPC does not collect, store, or transmit any personal data to external servers. All cryptographic keys are stored locally on your device and optionally synced to your personal iCloud Keychain. No analytics, advertising identifiers, or tracking data are collected."

### Privacy Usage Descriptions (already in Info.plist)

| Permission | Usage String |
|------------|-------------|
| Camera | CB-MPC uses the camera to scan QR codes for key transfer between devices. |
| Face ID | Unlock CB-MPC to access your cryptographic keys. |
| Local Network | This app needs to access your local network to communicate with MPC peers. |
| Location (When In Use) | This app may use location to identify local network peers. |

---

## App Review Information

### Contact Information

| Field | Value |
|-------|-------|
| First Name | Mark |
| Last Name | Phillips |
| Phone Number | 760-507-7572 |
| Email Address | roooot@atsignhandle.xyz |

### Sign-In Required?

**No** — the app does not require sign-in. Keys are generated locally.

### Notes for Reviewer

```
This app performs threshold multi-party computation (MPC) for cryptographic
key management. No server account is required for basic functionality.

To test core features:
1. Launch the app and tap "Create New Vault"
2. Tap "+" on the Keys tab to generate a new key
3. Select the key to view details, sign messages, or export

The app uses:
- Camera: for scanning QR codes during key import/export between devices
- Face ID: optional biometric lock to protect key access
- Local Network: for peer-to-peer MPC signing between paired devices
- Bonjour (_cbmpc._tcp): device discovery on local network

Encryption declaration: ITSAppUsesNonExemptEncryption = NO
(Uses Apple's built-in CryptoKit; no custom encryption exported)
```

---

## Version Information (TestFlight Build)

| Field | Value |
|-------|-------|
| Version | 0.17.0 |
| Build | 67 |
| What's New (TestFlight) | See below |

### TestFlight "What to Test" Text

```
Key MGMT wCB-MPC provides threshold cryptographic key management using
2-party MPC. Your private key never exists in one place.

Please test:
- Key generation (tap + on Keys tab)
- Message signing (tap a key → Sign Message)
- QR export/import (tap a key → Export → QR Code)
- Device pairing (Network tab → Pair Device)
- Server registration (Network tab → Register Server)
- Face ID lock (Settings → Face ID toggle)
- HD key derivation (Key detail → Derive Child Key)
- Multiple Ethereum network support (Settings → Networks)
```

---

## App Description (for App Store listing, not needed for TestFlight)

### Promotional Text (170 chars max)

```
Threshold key management powered by multi-party computation. Your private key never exists whole on any single device.
```

### Description (4000 chars max)

```
Key MGMT wCB-MPC is a threshold cryptographic key manager built on Coinbase's
open-source multi-party computation (MPC) library. Your private key is split
into shares — it never exists in one place.

THRESHOLD KEY MANAGEMENT
Generate secp256k1 keys using distributed key generation (DKG). Each key is
split into two shares stored separately — on your device, in iCloud Keychain,
on a paired device, or on a registered MPC server. Signing requires both
shares to cooperate, but neither share ever leaves its host.

2-PARTY MPC SIGNING
Sign messages and Ethereum transactions without ever reconstructing the
private key. The two key shares perform a cryptographic protocol that produces
a valid ECDSA signature without either party learning the other's share.

MULTI-DEVICE PAIRING
Pair iPhones over your local network using QR codes and MultipeerConnectivity.
One device holds share 0, the paired device holds share 1. True 2-party
security with no trusted server.

SERVER CO-SIGNING
Register a remote MPC key server to hold one share. The server participates
in DKG and signing over WebSocket, providing always-available co-signing
without custodial risk.

HD KEY DERIVATION
Derive child keys from any master key using BIP-32 compatible hierarchical
deterministic derivation — performed as a 2-party MPC protocol.

QR KEY TRANSFER
Export and import key shares via multi-frame QR codes. Transfer keys between
devices without any network connection.

SECURITY
- Keys protected by iOS Keychain with biometric (Face ID) access control
- Optional iCloud Keychain sync for backup
- Built on Coinbase's audited cb-mpc C++ library (Cure53 audit)
- secp256k1 curve (Bitcoin/Ethereum compatible)
- No analytics, no tracking, no data collection

ETHEREUM SUPPORT
- Sign raw messages and EIP-155 transactions
- Verify signatures against public keys
- Multiple networks: Mainnet, Sepolia, Base, Arbitrum, Optimism, Polygon, BSC
- Etherscan integration for address lookup

EDUCATIONAL DEMOS
Built-in interactive demos for ECDSA, EdDSA, zero-knowledge proofs,
N-party computation, batch signing, key lifecycle, and access structures.
```

### Keywords (100 chars max, comma-separated)

```
mpc,threshold,crypto,key,wallet,ecdsa,signing,secp256k1,ethereum,security
```

---

## Screenshots (Required for App Store, optional for TestFlight)

**Not required for TestFlight internal testing.** When ready for public TestFlight or App Store:

| Device | Size | Count Needed |
|--------|------|-------------|
| iPhone 6.7" (15 Pro Max) | 1290 x 2796 | 3-10 |
| iPhone 6.5" (11 Pro Max) | 1242 x 2688 | 3-10 |
| iPad Pro 12.9" (6th gen) | 2048 x 2732 | 3-10 (if supporting iPad) |

Suggested screenshot sequence:
1. Welcome/onboarding screen
2. Key dashboard with keys listed
3. Key detail view showing public key and actions
4. Sign message sheet
5. QR export in progress
6. Network tab showing paired devices
7. Settings view

---

## Encryption Export Compliance

| Question | Answer |
|----------|--------|
| Does your app use encryption? | **Yes** (CryptoKit, OpenSSL) |
| Is it exempt from export compliance? | **Yes** — `ITSAppUsesNonExemptEncryption = NO` in Info.plist |
| Reason | Uses only standard Apple CryptoKit and authentication (not custom encryption for data confidentiality transmitted over a network) |

> Note: The app uses OpenSSL internally for MPC computations but does not transmit encrypted data over the internet for confidentiality purposes. The MPC protocol is used for key generation and signing, which falls under the authentication exemption. If unsure, consult legal counsel or file for an ERN (Encryption Registration Number).

---

## Checklist Before Uploading to TestFlight

- [ ] Archive build in Xcode (Product → Archive)
- [ ] Upload to App Store Connect via Xcode Organizer
- [ ] Wait for build processing (5-15 min)
- [ ] Fill in "What to Test" for the build
- [ ] Add internal testers (your Apple ID is auto-added)
- [ ] Set up App Privacy responses
- [ ] Provide Privacy Policy URL
- [ ] Complete Export Compliance (confirm encryption exemption)
- [ ] Enable TestFlight testing for the build

---

## Fields You Must Fill In

| Field | Status |
|-------|--------|
| Privacy Policy URL | DONE — `https://cb-mpc-key-server.atsignhandle.workers.dev/privacy` |
| App Review Contact Info | DONE — Mark Phillips, roooot@atsignhandle.xyz, 760-507-7572 |
| Screenshots | Optional for internal TestFlight, required for public/App Store |
| Category (Primary) | Select "Utilities" in dropdown |
| Category (Secondary) | Select "Finance" (optional) |
| Content Rights | Click "Set Up" and confirm no third-party content |
| Age Ratings | Click "Set Up" and answer None to all |
