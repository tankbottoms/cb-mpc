# CB-MPC iOS App -- UX Workflows

Comprehensive reference for every user flow in the CB-MPC iOS application. This document supplements the existing visual guides with detailed step-by-step workflow descriptions, data flow diagrams, and technical notes.

---

## Table of Contents

- [1. Overview and Architecture](#1-overview-and-architecture)
  - [1.1 App Stack](#11-app-stack)
  - [1.2 Data Flow](#12-data-flow)
  - [1.3 Visual Guides (Existing)](#13-visual-guides-existing)
- [2. App Launch and Navigation](#2-app-launch-and-navigation)
  - [2.1 Tab Bar Structure](#21-tab-bar-structure)
  - [2.2 Platform-Specific Navigation](#22-platform-specific-navigation)
- [3. Key Dashboard](#3-key-dashboard)
  - [3.1 Empty State](#31-empty-state)
  - [3.2 Key List](#32-key-list)
  - [3.3 Instruction Levels](#33-instruction-levels)
  - [3.4 Swipe-to-Delete](#34-swipe-to-delete)
  - [3.5 Drag-to-Reorder](#35-drag-to-reorder)
- [4. Key Creation](#4-key-creation)
  - [4.1 Creation Modes](#41-creation-modes)
  - [4.2 Generate (DKG)](#42-generate-dkg)
  - [4.3 From Seed Phrase](#43-from-seed-phrase)
  - [4.4 From Private Key](#44-from-private-key)
  - [4.5 From QR Code](#45-from-qr-code)
  - [4.6 From Storage (File Import)](#46-from-storage-file-import)
  - [4.7 Key Types](#47-key-types)
  - [4.8 Derivation Presets](#48-derivation-presets)
  - [4.9 Post-Creation Behavior](#49-post-creation-behavior)
- [5. Key Detail View](#5-key-detail-view)
  - [5.1 Header and Name Editing](#51-header-and-name-editing)
  - [5.2 Public Key Display](#52-public-key-display)
  - [5.3 Metadata Section](#53-metadata-section)
  - [5.4 Operations Bar](#54-operations-bar)
  - [5.5 Signing History (Inline)](#55-signing-history-inline)
  - [5.6 Sheet Management](#56-sheet-management)
- [6. Message Signing](#6-message-signing)
  - [6.1 Signing Flow](#61-signing-flow)
  - [6.2 Nonce Generation](#62-nonce-generation)
  - [6.3 SHA-256 Hash Display](#63-sha-256-hash-display)
  - [6.4 Server Submission](#64-server-submission)
- [7. Transaction Signing](#7-transaction-signing)
  - [7.1 Network Selection](#71-network-selection)
  - [7.2 Gas Oracle Integration](#72-gas-oracle-integration)
  - [7.3 Transaction Fields](#73-transaction-fields)
  - [7.4 Transaction Preview](#74-transaction-preview)
  - [7.5 Live Data Refresh](#75-live-data-refresh)
- [8. Signature Verification](#8-signature-verification)
  - [8.1 Record-Based Verification](#81-record-based-verification)
  - [8.2 Manual Verification](#82-manual-verification)
  - [8.3 Verification Result Display](#83-verification-result-display)
- [9. QR Export and Import Cycle](#9-qr-export-and-import-cycle)
  - [9.1 Multi-Part QR Encoding](#91-multi-part-qr-encoding)
  - [9.2 QR Export Sheet](#92-qr-export-sheet)
  - [9.3 QR Scanner and Reassembly](#93-qr-scanner-and-reassembly)
  - [9.4 Transfer Passphrase](#94-transfer-passphrase)
  - [9.5 Binary Frame Format](#95-binary-frame-format)
- [10. Key Export](#10-key-export)
  - [10.1 Export Destinations](#101-export-destinations)
  - [10.2 KeyStore V3 JSON Format](#102-keystore-v3-json-format)
  - [10.3 UTC Filename Convention](#103-utc-filename-convention)
- [11. Signing History](#11-signing-history)
  - [11.1 History List View](#111-history-list-view)
  - [11.2 Detail Sheet](#112-detail-sheet)
  - [11.3 Clear All](#113-clear-all)
- [12. Settings](#12-settings)
  - [12.1 Ethereum RPC Configuration](#121-ethereum-rpc-configuration)
  - [12.2 Server Configuration](#122-server-configuration)
  - [12.3 Export Format](#123-export-format)
  - [12.4 Security (Face ID and Password)](#124-security-face-id-and-password)
  - [12.5 Key Naming Preferences](#125-key-naming-preferences)
  - [12.6 QR Transfer Speed](#126-qr-transfer-speed)
  - [12.7 Display Preferences](#127-display-preferences)
  - [12.8 Sync and Backup](#128-sync-and-backup)
  - [12.9 App Info](#129-app-info)
- [13. Security Model](#13-security-model)
  - [13.1 Key Storage Architecture](#131-key-storage-architecture)
  - [13.2 Face ID and Password Lock](#132-face-id-and-password-lock)
  - [13.3 Keychain Sync](#133-keychain-sync)
  - [13.4 Encryption for QR Transfer](#134-encryption-for-qr-transfer)
  - [13.5 2-Party MPC Share Model](#135-2-party-mpc-share-model)
- [14. Network Support Matrix](#14-network-support-matrix)
- [15. Error Handling Patterns](#15-error-handling-patterns)
  - [15.1 API Errors](#151-api-errors)
  - [15.2 Cryptographic Errors](#152-cryptographic-errors)
  - [15.3 QR Codec Errors](#153-qr-codec-errors)
  - [15.4 Key Data Errors](#154-key-data-errors)
  - [15.5 Network Connectivity](#155-network-connectivity)

---

## 1. Overview and Architecture

### 1.1 App Stack

The CB-MPC iOS app follows a layered architecture:

```
SwiftUI Views
    |
Swift Wrappers / Models (KeyStore, ManagedKey, EtherscanService)
    |
Bridging Header
    |
C API (cbmpc_ios.h)
    |
libcbmpc.a (C++)
    |
OpenSSL + secp256k1
```

- **Views** are pure SwiftUI, organized as sheets presented from detail views.
- **KeyStore** is the central `@MainActor ObservableObject` that manages all key CRUD operations, signing records, and persistence via CoreData.
- **CBMPCCryptoEngine** wraps the C++ MPC library for key generation, signing, and verification.
- **EtherscanService** provides live blockchain data via the Etherscan v2 API.
- **MultiQRCodec** handles binary framing, compression (zlib), and encryption (AES-256-GCM) for QR code transfers.

### 1.2 Data Flow

```
CoreData (ManagedKeyEntity, SigningRecordEntity)
    |
    v
KeyStore (in-memory [ManagedKey] array)
    |
    v
Views (@EnvironmentObject keyStore)

Key Material (2-party shares):
    UserDefaults["key_{UUID}"] --> [4-byte k0 length][k0 bytes][k1 bytes]
```

- Key metadata lives in CoreData (name, public key, type, derivation path, timestamps).
- Key material (the actual MPC shares) is stored in `UserDefaults` keyed by `key_{UUID}`.
- Signing records are CoreData entities with a relationship to their parent `ManagedKeyEntity`.

### 1.3 Visual Guides (Existing)

The following HTML visual guides provide diagrams and illustrations. They remain the primary visual reference alongside this document:

- [CB-MPC Visual Guide](cb-mpc-visual-guide.html) -- Architecture overview, key lifecycle, data flow diagrams.
- [CB-MPC Threshold Signing Visual Guide](cb-mpc-threshold-signing%E2%80%94visual-guide.html) -- Multi-party computation protocol details, threshold signing sequences.

---

## 2. App Launch and Navigation

### 2.1 Tab Bar Structure

The app uses a floating custom tab bar (`FloatingTabBar`) with four tabs:

| Tab Index | Label    | View                | Purpose                              |
|-----------|----------|---------------------|--------------------------------------|
| 0         | Keys     | `KeyDashboardView`  | Key list, creation entry point       |
| 1         | History  | `SigningHistoryView` | All signing records across all keys  |
| 2         | Demos    | `DemoHubView`       | Demo/playground views                |
| 3         | Settings | `SettingsView`      | App configuration                    |

Tab state is persisted via `@SceneStorage("selectedTab")`.

### 2.2 Platform-Specific Navigation

- **iPhone**: Custom `FloatingTabBar` at the bottom with `ZStack` layout. Each tab contains its own `NavigationStack`.
- **macOS**: `NavigationSplitView` with a sidebar key list and detail pane.
- **iPad**: `NavigationSplitView` with automatic column visibility.

---

## 3. Key Dashboard

Entry point: Tab 0 (`KeyDashboardView`).

### 3.1 Empty State

When `keyStore.keys.isEmpty`, the view shows a `ContentUnavailableView` with:

- System image: `key.slash`
- Title: "No Keys"
- Description: "Create your first key to get started"

### 3.2 Key List

Each key is rendered by `KeyListItemView` showing:

- **Line 1**: Key name (monospaced, semibold), shield icon (orange, indicating 2-party local), validity indicator (green checkmark if key data exists in UserDefaults, red X if missing).
- **Line 2**: Truncated public key (first 32 characters + "..."), key type label (ECDSA, HD-MASTER, or HD-CHILD).

Tapping a key navigates to `KeyDetailView` via `NavigationLink`.

Newly added keys receive a blue highlight animation that pulses 5 times then fades. The `recentlyAddedKeyId` on `KeyStore` tracks which key was just created.

### 3.3 Instruction Levels

Controlled by `@AppStorage("instructionLevel")` with three modes:

- **verbose**: Full paragraph explaining DKG, MPC shares, and key types.
- **minimal**: Short hint: "Tap + to create a new key. Swipe left to delete."
- **off**: No instruction section displayed.

### 3.4 Swipe-to-Delete

Standard SwiftUI `.onDelete` modifier. Swipe left on any key row to reveal the delete action. Calls `keyStore.deleteKey(key.id)` which:

1. Removes the CoreData entity.
2. Removes key data from `UserDefaults`.
3. Reloads the key list.

### 3.5 Drag-to-Reorder

Standard SwiftUI `.onMove` modifier. Keys can be reordered by long-pressing and dragging. Calls `keyStore.moveKeys(from:to:)` which updates `sortOrder` on all keys and persists to CoreData.

---

## 4. Key Creation

Entry point: "+" button in the toolbar of `KeyDashboardView` opens `CreateKeySheetView` as a sheet.

### 4.1 Creation Modes

The creation sheet uses a segmented picker across the top with five modes:

| Mode             | Enum Case        | Description                              |
|------------------|------------------|------------------------------------------|
| Generate         | `.generate`      | DKG key generation via C++ engine        |
| Seed             | `.importSeed`    | Import from BIP-39 seed phrase           |
| Private          | `.importPrivateKey` | Import from raw hex private key       |
| Storage          | `.importUSB`     | Import from a KeyStore V3 JSON file      |
| QR Code          | `.importQR`      | Scan multi-part QR codes from another device |

### 4.2 Generate (DKG)

Flow:

1. User selects key type (ECDSA, HD-MASTER, or HD-CHILD).
2. For HD-CHILD: user selects a parent HD-MASTER key and derivation path.
3. User can optionally set a custom name (auto-generated default uses short address + timestamp).
4. Tap "Create Key" button.
5. `keyStore.generateCryptographicKey(name:keyType:)` is called on a background thread.
6. The C++ engine runs 2-party DKG, producing a compressed SEC1 public key (33 bytes for secp256k1) and serialized key shares.
7. Key shares are stored in `UserDefaults`, metadata in CoreData.
8. Sheet dismisses; dashboard shows the new key with blue highlight.

Key type options:

- **ECDSA** (`simple`): Standard signing key.
- **HD-MASTER** (`hdMaster`): Root key for hierarchical derivation. Derivation path is set to "m".
- **HD-CHILD** (`hdChild`): Derived from an HD-MASTER. Requires selecting parent key and BIP-44 path.

### 4.3 From Seed Phrase

Flow:

1. User selects "Seed" mode.
2. Selects word count (12 or 24 words).
3. Enters or pastes BIP-39 mnemonic phrase.
4. Can toggle reveal/hide of the seed phrase text.
5. Selects derivation preset (Ledger, MetaMask, Custom).
6. Tap "Import" to generate the key from the seed.

The key type is forced to `hdMaster` for seed imports.

### 4.4 From Private Key

Flow:

1. User selects "Private" mode.
2. Enters raw hex private key (with or without 0x prefix).
3. Selects key type.
4. Tap "Import" to create the key from the private key material.

### 4.5 From QR Code

Flow:

1. User selects "QR Code" mode.
2. Tap "Scan QR Code" to open `QRScannerView`.
3. Scanner captures multi-part QR codes (see [Section 9](#9-qr-export-and-import-cycle)).
4. On completion, the scanned parts are decoded via `MultiQRCodec.decode`.
5. A passphrase prompt appears for decryption.
6. The decoded KeyStore JSON is parsed and the key is imported.

### 4.6 From Storage (File Import)

Flow:

1. User selects "Storage" mode.
2. Tap "Select File" to open a `UIDocumentPickerViewController` for `.json` files.
3. The selected KeyStore V3 JSON file is parsed.
4. Filename and address are displayed for confirmation.
5. Tap "Import" to create the key from the file contents.

### 4.7 Key Types

| Type       | Raw Value    | Display    | Description                         |
|------------|-------------|------------|-------------------------------------|
| Simple     | `simple`    | ECDSA      | Standard ECDSA signing key          |
| HD Master  | `hdMaster`  | HD-MASTER  | BIP-32 master key for derivation    |
| HD Child   | `hdChild`   | HD-CHILD   | Derived key from an HD-MASTER       |

All keys use curve code 714 (secp256k1).

### 4.8 Derivation Presets

| Preset   | Path               | Description                            |
|----------|--------------------|----------------------------------------|
| Ledger   | `m/44'/60'/0'`     | Ledger Live default                    |
| MetaMask | `m/44'/60'/0'/0`   | MetaMask default for imported seeds    |
| Custom   | (user-entered)     | Any BIP-44 compatible path             |

### 4.9 Post-Creation Behavior

After successful creation:

1. `keyStore.addKey(key)` persists to CoreData.
2. `recentlyAddedKeyId` is set, triggering the blue highlight animation.
3. The highlight clears after 3 seconds.
4. The sheet auto-dismisses.

---

## 5. Key Detail View

Entry point: Tap a key in `KeyDashboardView` to navigate to `KeyDetailView`.

### 5.1 Header and Name Editing

- Key name is displayed in headline monospaced font.
- Tap the name to enter inline edit mode (text field with confirm/cancel buttons).
- Saves via `keyStore.updateKeyName(keyId, newName:)`.
- Key type label (ECDSA, HD-MASTER, HD-CHILD) appears below the name.
- QR icon in the top-right opens the public key QR share sheet.

### 5.2 Public Key Display

- Full public key is displayed in two lines (3/4 on top, 1/4 on bottom) with `0x` prefix.
- Copy button next to the second line copies the full `0x`-prefixed key.
- Text is selectable.
- Derivation path shown below (if applicable).

### 5.3 Metadata Section

Displayed in a rounded gray card:

| Field               | Content                                                |
|---------------------|--------------------------------------------------------|
| Curve               | `secp256k1 (714)`                                      |
| Derivation Standard | Ledger Live, MetaMask, or Custom (for HD keys)         |
| HD Master           | Link to parent key (for HD-CHILD keys only)            |
| Derivation Path     | Full BIP-44 path with copy button                      |
| Storage             | "Secure Enclave" or "Keychain"                         |
| Created             | Timestamp in `yyyyMMdd-HHmmss` format                  |
| Source              | "Imported" (only shown if `isBackedUp` is true)        |
| Last Used           | Timestamp of last signing operation                    |
| Filename            | UTC-formatted KeyStore filename                        |
| iCloud Path         | `iCloud/Key-MGMT-CB-MPC/{filename}.json`               |

Security indicator banner: "2-PARTY LOCAL -- Both key shares stored on this device" in orange.

### 5.4 Operations Bar

Conditionally displayed based on key state:

**If key data exists** (valid MPC shares in UserDefaults):

- **Sign** (blue, prominent) -- Opens `SignMessageSheetView`.
- **Sign Tx** (orange, prominent) -- Opens `SignTransactionSheetView`.

**If key data is missing**:

- Warning: "No key data -- regenerate this key to enable signing"

**Always available**:

- **Verify** (bordered, mini) -- Opens `VerifySignatureSheetView`. Disabled if no signing records exist.
- **Derive** (bordered, mini) -- Opens derive child sheet. Only shown for HD-MASTER keys.
- **Export** (bordered, mini) -- Opens `ExportKeySheetView`.

### 5.5 Signing History (Inline)

The last 10 signing records are displayed inline in the key detail view, each showing:

- Timestamp + key type + delete button + verified badge.
- Full SHA-256 hash with copy button.
- Full signature with copy button.
- Tap to share the full record via system share sheet.

### 5.6 Sheet Management

`KeyDetailView` uses an enum-based sheet system (`KeyDetailSheet`) to manage all presented sheets:

```
enum KeyDetailSheet: Identifiable {
    case signing    // SignMessageSheetView
    case signTx     // SignTransactionSheetView
    case verify     // VerifySignatureSheetView
    case qrShare    // Public key QR code
    case derive     // HD child derivation
    case export     // ExportKeySheetView
}
```

Only one sheet can be active at a time via `@State private var activeSheet: KeyDetailSheet?`.

---

## 6. Message Signing

Entry point: "Sign" button in `KeyDetailView` opens `SignMessageSheetView`.

### 6.1 Signing Flow

1. User enters a plaintext message in the text editor.
2. A UUID v4 nonce is auto-generated (can be refreshed with the cycle button).
3. SHA-256 hash of the message is displayed in real time below the input.
4. Tap "Sign Message" button.
5. The message is concatenated with the nonce: `"{message}|{nonce}"`.
6. SHA-256 hash is computed on the concatenated string.
7. `CBMPCCryptoEngine.signMessage` is called on a background thread with the hash, key data, and curve code.
8. The resulting DER-encoded ECDSA signature is displayed as uppercase hex.
9. Signature is auto-copied to clipboard with success haptic feedback.
10. A `SigningRecord` is created and added to the key's history via `keyStore.addSigningRecord`.

After signing, the button row changes to:

- **Copy** -- Copies signature to clipboard.
- **Submit** -- Opens `ServerSubmitResultView` (only if a signing server URL is configured).
- **Done** -- Dismisses the sheet (shown when no server URL is configured).

### 6.2 Nonce Generation

- Generated using `UUID().uuidString` (122 bits of randomness).
- Displayed in uppercase.
- Can be regenerated by tapping the refresh icon.
- Purpose: Prevents replay attacks by binding each signature to a single-use token.

### 6.3 SHA-256 Hash Display

- Computed in real time as the user types.
- Displayed as uppercase hex directly below the message input.
- Uses CryptoKit `SHA256.hash(data:)`.

### 6.4 Server Submission

If `signingServerURL` is configured (not the default placeholder):

1. A "Submit" button appears after signing.
2. Tapping opens `ServerSubmitResultView` showing nonce, signature, with copy buttons.
3. "Submit" sends to the signing server via `SigningServerClient.shared.submit`.
4. Payload includes: nonce, publicKey, signature, message, serverURL.
5. Success: auto-dismisses both sheets.
6. Failure: displays error message inline.

---

## 7. Transaction Signing

Entry point: "Sign Tx" button in `KeyDetailView` opens `SignTransactionSheetView`.

### 7.1 Network Selection

Tap the network indicator bar at the top to open `NetworkSelectorSheet`:

- Networks are split into Mainnets and Testnets sections.
- Currently selected network has a blue checkmark.
- Networks without gas oracle support show a yellow warning icon.
- Selecting a network clears stale data and refreshes live data.
- Selection is persisted via `@AppStorage("ethereumRPC")`.

### 7.2 Gas Oracle Integration

On view appear and on manual refresh, the app fetches from Etherscan v2 API:

1. **Gas Oracle**: Safe, Standard, and Fast gas prices in gwei + base fee, block number, gas used ratio.
2. **ETH Price**: Current ETH/USD rate.
3. **Balance**: Account balance in ETH (from public key).

Gas oracle data is displayed as three columns (SAFE/STANDARD/FAST) with gwei values and USD equivalents. Tapping opens a detailed gas tracker sheet with:

- Full gas oracle details (base fee, block, gas used ratio).
- Quick-apply buttons: "Use Safe", "Use Standard", "Use Fast".
- Share button for gas tracker text export.

### 7.3 Transaction Fields

| Field                   | Default    | Description                     |
|-------------------------|------------|---------------------------------|
| NONCE                   | "0"        | Transaction nonce               |
| TO ADDRESS              | (empty)    | Recipient 0x address            |
| VALUE (ETH)             | "0.01"     | Amount in ETH                   |
| GAS LIMIT               | "21000"    | Gas units                       |
| GAS PRICE (GWEI)        | "20" / oracle | Gas price, auto-filled from oracle |
| PRIORITY FEE (GWEI)     | "1.5"      | EIP-1559 max priority fee       |
| DATA (HEX)              | (empty)    | Optional calldata               |
| CHAIN ID                | (read-only)| Derived from selected network   |

Each field with a numeric value shows a USD equivalent when ETH price is available.

### 7.4 Transaction Preview

A read-only JSON preview is rendered below the input fields, showing the full transaction object with all fields. Actions:

- **Copy** -- Copies the transaction JSON to clipboard.
- **Share** -- Opens system share sheet with the transaction JSON.

### 7.5 Live Data Refresh

- Automatic on view appear.
- Manual via the refresh button in the toolbar.
- Network errors display an alert with "Change Network" and "OK" options.
- Loading state shows a mini progress indicator next to the balance/price row.

---

## 8. Signature Verification

Entry point: "Verify" button in `KeyDetailView` opens `VerifySignatureSheetView`.

### 8.1 Record-Based Verification

1. Existing signing records for the key are listed (up to 10).
2. Each record shows timestamp, key name, hash, and signature with copy buttons.
3. Tap a record to verify it.
4. Verification calls `CBMPCCryptoEngine.verifySignature` with: curve code, public key bytes, message hash bytes, and DER signature bytes.
5. Result appears inline: green "Valid" or red "Invalid" badge with haptic feedback.

### 8.2 Manual Verification

1. Tap "Manual Verification" to expand the manual entry section.
2. Enter: message text, nonce (optional), signature hex.
3. If nonce is provided, the full message is constructed as `"{message}|{nonce}"` (matching the signing flow).
4. SHA-256 hash is computed from the full message.
5. Tap "Verify" to run ECDSA verification against the key's public key.

### 8.3 Verification Result Display

- **Valid**: Green shield icon, "Signature is valid", green background.
- **Invalid**: Red shield icon, "Signature is invalid", red background.
- **Error**: Red exclamation icon with error description (e.g., "Invalid public key hex", "Invalid signature hex").
- Haptic feedback: success notification for valid, error notification for invalid.

---

## 9. QR Export and Import Cycle

The QR system enables device-to-device key transfer using animated multi-part QR codes.

### 9.1 Multi-Part QR Encoding

The encoding pipeline (`MultiQRCodec` / `ExportKeySheetView.encodeForQR`):

1. **CRC32 checksum** of the original JSON.
2. **Zlib compression** of the JSON data.
3. **AES-256-GCM encryption** using a key derived from a random passphrase via HKDF-SHA256 with salt "CBMPC-MultiQR-v1".
4. **Chunking** into parts that fit within ~450 bytes binary (~600 chars base64, QR version 9-10).
5. **Framing** each chunk with a binary header containing magic bytes, version, part number, total parts, and (for part 0) compression/encryption metadata, original size, nonce, and CRC32.

### 9.2 QR Export Sheet

Entry point: "Export" button in `KeyDetailView` opens `ExportKeySheetView`.

Display:

- **QR code image** (200x200 px, white background, nearest-neighbor interpolation).
- For multi-part exports: auto-cycling animation at configurable speed (default 1.5s).
- Dot indicators showing current part position.
- Tap QR to pause/resume cycling.
- Tap individual dots to jump to a specific part.
- Part counter: "Part X of Y".
- UTC filename display.
- Export data (full KeyStore JSON) with copy button.
- Backup destinations (see [Section 10](#10-key-export)).
- Transfer passphrase with copy button.

The QR codes are generated asynchronously via `.task` on sheet appear. A loading spinner shows "Encoding..." until ready.

### 9.3 QR Scanner and Reassembly

Entry point: "QR Code" mode in `CreateKeySheetView` opens `QRScannerView`.

Flow:

1. Camera preview fills the screen with a semi-transparent overlay at the bottom.
2. Instructions: "Point camera at the rotating QR codes" / "Each part will be captured automatically".
3. Each scanned QR code is base64-decoded, then validated:
   - Must be at least 10 bytes.
   - Must start with magic bytes `0x43 0x42 0x4D 0x50 0x43` ("CBMPC").
   - Part number and total parts are extracted from the header.
   - Total parts must be consistent across all scanned codes.
4. Progress display: "X of Y parts scanned" with dot indicators (green = captured, gray = pending).
5. Duplicate detection: the same QR content string is never processed twice.
6. Each successful scan triggers a medium haptic impact.
7. When all parts are captured: success haptic, ordered parts delivered via callback, scanner auto-dismisses.

### 9.4 Transfer Passphrase

- A 16-character random passphrase is generated from 16 random bytes, base64-encoded and truncated.
- Displayed on the export sheet for the user to communicate to the receiving device.
- Required on the receiving device to decrypt the QR payload.
- Derived into an AES-256 key using HKDF-SHA256.

### 9.5 Binary Frame Format

```
Common Header (10 bytes):
  [0..4]   Magic: 0x43 0x42 0x4D 0x50 0x43 ("CBMPC")
  [5]      Version: 0x01
  [6..7]   Part Number (uint16, big-endian)
  [8..9]   Total Parts (uint16, big-endian)

Part 0 Extra Header (22 bytes, only in first part):
  [10]     Compression Type: 0x01 = zlib
  [11]     Encryption Type: 0x01 = AES-256-GCM
  [12..15] Original Size (uint32, big-endian)
  [16..27] AES-GCM Nonce (12 bytes)
  [28..31] CRC32 Checksum (uint32, big-endian)

Payload:
  [header_end..] Encrypted + compressed chunk data
```

Each frame is base64-encoded for QR code compatibility.

---

## 10. Key Export

### 10.1 Export Destinations

The export sheet offers three backup destinations:

| Destination       | Icon             | Storage Method                                |
|-------------------|------------------|-----------------------------------------------|
| Secure Enclave    | `lock.shield`    | Local Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) |
| iCloud Keychain   | `key.icloud`     | Synced Keychain via `KeychainSyncManager` (`kSecAttrSynchronizable: true`) |
| Storage           | `externaldrive`  | System share sheet for file export             |

Each destination shows a checkmark after successful export. Status messages display the filename and timestamp.

### 10.2 KeyStore V3 JSON Format

The export format follows the Ethereum KeyStore V3 standard with a `cb-mpc` extension:

```json
{
  "version": 3,
  "id": "{uuid}",
  "address": "{last 40 chars of public key}",
  "crypto": {
    "cipher": "aes-128-ctr",
    "cipherparams": { "iv": "" },
    "ciphertext": "",
    "kdf": "scrypt",
    "kdfparams": { "dklen": 32, "n": 262144, "p": 1, "r": 8, "salt": "" },
    "mac": ""
  },
  "cb-mpc": {
    "name": "{key name}",
    "publicKey": "{hex public key}",
    "keyType": "simple|hdMaster|hdChild",
    "curveCode": 714,
    "createdAt": "{ISO8601}",
    "storageLocation": "secureEnclave|keychain",
    "keyData": "{base64-encoded MPC shares}",
    "derivationPath": "{BIP-44 path, if applicable}",
    "parentKeyId": "{UUID, if HD-CHILD}"
  }
}
```

Note: QR exports use a compact version that strips `keyData` from the `cb-mpc` section to fit within QR capacity.

### 10.3 UTC Filename Convention

Format: `UTC--{yyyy-MM-dd'T'HH-mm-ss.SSS'Z'}--{address}.json`

Example: `UTC--2026-03-07T14-30-45.123Z--a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2.json`

---

## 11. Signing History

Entry point: Tab 1 (`SigningHistoryView`).

### 11.1 History List View

- Aggregates all signing records across all keys, sorted newest first.
- Each row shows:
  - Verified status icon (green checkmark or red X).
  - Key name + key type label.
  - Timestamp.
  - Truncated signature (single line, middle truncation).
- Tap a row to open the detail sheet.
- Swipe left to delete individual records (with haptic feedback).
- Empty state: clock icon with "No signing history" message.

### 11.2 Detail Sheet

Presented as a sheet (`SigningDetailSheetView`) showing:

- Date, Key name, Key type, Public key (0x-prefixed), Verified status, SHA-256 hash, Signature.
- Each field has a copy button.
- "Copy All" button at the bottom copies a formatted plain-text record.

### 11.3 Clear All

- Trash icon in the toolbar.
- Confirmation alert: "Clear All History -- This will permanently delete all signing history records."
- Calls `keyStore.clearAllSigningRecords()` which deletes all `SigningRecordEntity` objects from CoreData.

---

## 12. Settings

Entry point: Tab 3 (`SettingsView`).

### 12.1 Ethereum RPC Configuration

- **Network Picker**: Dropdown menu with all supported networks (see [Section 14](#14-network-support-matrix)).
- **RPC URL**: Read-only display of the Infura base URL for the selected network.
- **Infura API Key**: Masked by default, tap eye icon to reveal/edit.
- **Etherscan API Key**: Masked by default, tap eye icon to reveal/edit.
- **Chain ID**: Read-only, derived from the selected network.

Footer: "Connects to the Ethereum network via Infura RPC for broadcasting transactions and querying on-chain state such as balances, nonces, and gas estimates."

### 12.2 Server Configuration

- **Server URL**: Editable text field for the DKG/MPC coordination server. Default: `https://api.cbmpc.atsignhandle.xyz`.
- **Signing Server**: Editable text field for the threshold signature assembly server. Default: `https://signing.cbmpc.atsignhandle.xyz/submit`.
- **Use Mock Server**: Toggle for local development.

Footer: "Server URL is used for distributed key generation (DKG) and multi-party computation coordination between parties. Signing Server handles commitment exchanges and threshold signature assembly for transaction signing."

### 12.3 Export Format

Read-only display: "KeyStore V3 JSON". This is the only supported export format.

Footer: "KeyStore V3 JSON includes MPC key shares for full backup and restore capability."

### 12.4 Security (Face ID and Password)

- **Face ID Toggle**: Enables biometric authentication on app launch. Stored in `@AppStorage("useFaceID")`.
- **Password**: Tap to open `PasswordSetupSheetView`.
  - Set or change a password (minimum 4 characters).
  - Password is hashed with SHA-256 and stored as hex in `@AppStorage("keystorePasswordHash")`.
  - Shows "Enabled" (green) with the set date, or "Disabled" (gray).
  - Option to remove password.

Footer: "Protects access to keys and signing operations. Face ID provides biometric authentication on app launch. Password is required as fallback when Face ID is unavailable."

### 12.5 Key Naming Preferences

- **HD-CHILD uses own address**: Toggle controlling how HD-CHILD keys are named.
  - Off (default): Named as `{HD-MASTER 0x address}/{account number} {timestamp}`.
  - On: Named using the child key's own `0x` address.

### 12.6 QR Transfer Speed

- **Cycle Speed**: Slider from 0.5s to 3.0s in 0.25s increments. Default: 1.5s.
- Controls the auto-advance rate of animated multi-part QR codes in the export view.

### 12.7 Display Preferences

- **Instruction Level**: Picker with Off, Minimal, Verbose options. Controls the guidance text shown on the key dashboard.

### 12.8 Sync and Backup

- **Backup to iCloud Now**: Opens `BackupSheetView` which exports all keys to `iCloud/Documents/Key-MGMT-CB-MPC/` as individual KeyStore V3 JSON files.
  - Terminal-style log output shows progress.
  - Each key shows type, short address, file size, and filename.
  - Progress bar: "Backing up X/Y..."
  - Disabled when no keys exist.
- **Reset Demo Data**: Clears all keys and regenerates demo keys via `DemoDataGenerator.generateRealDemoKeys()`. Shows progress spinner during generation.

### 12.9 App Info

- **Version**: Read from `Info.plist` (`CFBundleShortVersionString` + `CFBundleVersion`).
- **Coinbase CB-MPC**: External link to `github.com/coinbase/cb-mpc`.
- **iOS Application**: External link to `github.com/tankbottoms/cb-mpc`.
- **Disclaimer**: Testing/evaluation only, not for production use.
- **Acknowledgements**: Credits Coinbase CB-MPC and the broader cryptocurrency research community.

---

## 13. Security Model

### 13.1 Key Storage Architecture

```
+-----------------------+     +-------------------------+
| CoreData              |     | UserDefaults            |
| ManagedKeyEntity      |     | key_{UUID} = Data       |
|   - id, name          |     |   [4-byte k0 len]       |
|   - publicKey          |     |   [k0 bytes]            |
|   - keyType           |     |   [k1 bytes]            |
|   - curveCode          |     +-------------------------+
|   - derivationPath    |
|   - sortOrder          |
|   - signingRecords --> |
+-----------------------+
```

- Key metadata is separate from key material.
- Key material format: `[4-byte k0 length (big-endian)][k0 bytes][k1 bytes]`, where k0 and k1 are the two MPC party shares.
- Both shares are stored locally (2-party local model).

### 13.2 Face ID and Password Lock

- Face ID: Uses the `LAContext` API for biometric authentication on app launch.
- Password: SHA-256 hash stored in `AppStorage`. Used as fallback when Face ID is unavailable.
- Both are opt-in settings (disabled by default).

### 13.3 Keychain Sync

`KeychainSyncManager` provides iCloud Keychain synchronization:

- Service identifier: `xyz.atsignhandle.cb-mpc.keychain-sync`.
- Account key: `keystore_{UUID}`.
- Accessibility: `kSecAttrAccessibleWhenUnlocked` (synced items).
- Synchronizable: `true` -- items sync across devices via iCloud Keychain.
- Operations: save, load, delete.

Local Secure Enclave export uses a different service (`xyz.atsignhandle.cb-mpc.keystore`) with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (no sync).

### 13.4 Encryption for QR Transfer

- Passphrase: 16-character random string (128 bits of entropy from `UInt8.random`).
- Key derivation: HKDF-SHA256 with salt "CBMPC-MultiQR-v1", 32-byte output.
- Encryption: AES-256-GCM with random 12-byte nonce.
- Integrity: CRC32 checksum on original data, verified after decryption and decompression.

### 13.5 2-Party MPC Share Model

All keys use 2-party threshold signatures:

- DKG produces two key shares (k0, k1) via the C++ `cbmpc` library.
- Neither share alone reveals the private key.
- Signing requires both shares cooperating in a multi-party protocol.
- In the current local mode, both shares reside on the same device (indicated by the orange "2-PARTY LOCAL" badge).
- Public keys are compressed SEC1 format (33 bytes for secp256k1, prefix 0x02 or 0x03).

---

## 14. Network Support Matrix

| Network            | ID Tag     | Chain ID  | Testnet | Gas Oracle | Native Currency |
|--------------------|-----------|-----------|---------|------------|-----------------|
| Ethereum Mainnet   | `mainnet`  | 1         | No      | Yes        | ETH             |
| Base               | `base`     | 8453      | No      | Yes        | ETH             |
| Arbitrum One       | `arbitrum` | 42161     | No      | Yes        | ETH             |
| Optimism           | `optimism` | 10        | No      | Yes        | ETH             |
| Polygon            | `polygon`  | 137       | No      | Yes        | MATIC           |
| BNB Smart Chain    | `bsc`      | 56        | No      | Yes        | BNB             |
| Sepolia Testnet    | `sepolia`  | 11155111  | Yes     | Yes        | ETH             |
| Hoodi Testnet      | `hoodi`    | 560048    | Yes     | No         | ETH             |

All networks use the Etherscan v2 API (`https://api.etherscan.io/v2/api`) with the `chainid` parameter for routing. The Infura RPC base URL changes per network (e.g., `https://mainnet.infura.io`, `https://base-mainnet.infura.io`).

Networks without gas oracle support (Hoodi) will show errors when gas data is fetched; the transaction form still functions with manual gas price entry.

---

## 15. Error Handling Patterns

### 15.1 API Errors

**Etherscan API errors**:

- The `EtherscanService` checks every response for error status (`status == "0"`).
- Errors are surfaced as `APIError.apiMessage(String)` with the API's result message.
- In `SignTransactionSheetView`, API errors accumulate across gas oracle, price, and balance calls.
- Non-critical errors (price fetch failure) are reported but do not block the transaction form.
- An alert dialog offers "Change Network" or "OK" options.

**Network selector feedback**: Networks without gas oracle support show a yellow warning triangle icon.

### 15.2 Cryptographic Errors

- Key generation failures throw `CBMPCError` from the C++ engine, caught and logged.
- Signing failures display an alert: "Signing failed: {error description}".
- Verification failures display inline error messages (e.g., "Invalid public key hex", "Invalid signature hex").
- The `CBMPCError.invalidKeyData` error is thrown when key material is missing from UserDefaults.

### 15.3 QR Codec Errors

`MultiQRCodec.CodecError` cases:

| Error                  | Cause                                              |
|------------------------|----------------------------------------------------|
| `compressionFailed`    | Zlib compression returned nil                      |
| `decompressionFailed`  | Zlib decompression returned nil                    |
| `encryptionFailed`     | AES-GCM seal operation failed                      |
| `decryptionFailed`     | AES-GCM open failed (wrong passphrase or corrupted data) |
| `invalidMagic`         | First 5 bytes do not match "CBMPC"                 |
| `invalidVersion`       | Version byte is not 0x01                           |
| `crcMismatch`          | CRC32 of decompressed data does not match header   |
| `missingParts`         | Not all expected parts were provided               |

QR scanner errors:

- "Not a CB-MPC QR code" -- Scanned QR does not have the CBMPC magic header.
- "QR code set mismatch" -- Part belongs to a different QR export (different total count).

### 15.4 Key Data Errors

- Missing key data: UserDefaults returns nil for `key_{UUID}`. The detail view shows a warning banner and disables signing operations.
- Invalid key data: C++ engine throws during signing; error propagated to the UI as an alert.

### 15.5 Network Connectivity

- All Etherscan API calls use `URLSession.shared.data(from:)` with standard error handling.
- Errors are collected per-call (gas, price, balance) and joined into a single alert message.
- The refresh button in the transaction view toolbar allows manual retry.
- iCloud backup failures are caught and displayed in the backup log terminal.
