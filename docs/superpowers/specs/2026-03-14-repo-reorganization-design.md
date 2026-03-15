# Repo Reorganization and Private-Ready Documentation

**Date**: 2026-03-14
**Status**: Draft
**Scope**: New private repo creation, documentation overhaul, secrets consolidation, icon cache, feature roadmap

---

## 0. New Private Repository

### Context

The current repo (`tankbottoms/cb-mpc`) is a **public fork** of `coinbase/cb-mpc`. GitHub does not allow forks to be made private. A new private repo must be created.

**Sensitive data already in public git history:**
- Apple Team ID `YT6VJY3L35` in committed files: `CBMPCNative/ExportOptions.plist`, `ExportOptions.plist` (root), `docs/ios/README.md`
- Note: `build-device.sh`, `device-build-setup.sh`, `update-project-device.sh` appear in `git grep` results but these files were committed in earlier history and may have been removed -- verify before cleanup
- Device UUIDs in various docs
- `.env` was never committed (safe)
- `ExportOptions-iOS-local.plist`, `ExportOptions-iOS.plist`, `ExportOptions-macOS-local.plist`, `ExportOptions-macOS.plist` are untracked (safe). These contain Team ID `YT6VJY3L35` and WILL be committed to the private repo (acceptable since repo is private).

**Prerequisites for evm's machine:**
- Xcode 16+ with command line tools
- Python 3 (`/usr/bin/python3`, ships with macOS)
- `gh` CLI (for GitHub operations): `brew install gh`
- App Store Connect `.p8` key file (obtain from team lead or shared credential store)

### Plan

1. Create new private repo: `tankbottoms/cb-mpc-ios`
2. Push full `ios` branch history as the default branch
3. Push `ios-macosx-swift-build` (renamed from `ios-integration-phase-1`) as a historical reference branch
4. Do NOT push: `master` (available on public fork), `exp-api`, `network-null-check`, `ios-integration-scratch`, `gh-pages`
5. Clean up sensitive values in committed files before first push (replace hardcoded team IDs with `.env.json` references)

### Commands

```bash
# Create new private repo on GitHub
gh repo create tankbottoms/cb-mpc-ios --private --description "CB-MPC iOS/macOS threshold key management app"

# Add as new remote
git remote add private git@tankbottoms.github.com:tankbottoms/cb-mpc-ios.git

# Rename phase-1 branch
git branch -m ios-integration-phase-1 ios-macosx-swift-build

# Push branches to private repo
git push private ios
git push private ios-macosx-swift-build

# Set ios as default branch on private repo
gh api repos/tankbottoms/cb-mpc-ios -X PATCH -f default_branch=ios
```

---

## 1. Branch Cleanup (Public Fork)

After the private repo is set up, clean up the public fork:

### Actions

| Branch | Action | Rationale |
|--------|--------|-----------|
| `ios-integration-scratch` (remote) | Delete from public fork | All 5 commits are a subset of phase-1 |
| `exp-api` (remote) | Delete from public fork | Pre-iOS C++ branch, not relevant |
| `network-null-check` (remote) | Delete from public fork | Pre-iOS C++ branch |
| `master` | Keep on public fork | Upstream C++ library |
| `ios` | Keep on public fork | Reference (active dev moves to private) |
| `gh-pages` | Keep on public fork | Published documentation |

### Commands

```bash
# Delete stale remote branches on public fork
git push origin --delete ios-integration-scratch
git push origin --delete exp-api
git push origin --delete network-null-check

# Clean up local tracking refs
git fetch --prune
```

---

## 2. Secrets Consolidation (.env.json)

### Current State

`.env` file with 6 shell variables, all actively used by 3 scripts:
- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_FILE` -- App Store Connect JWT auth
- `APPLE_STORE_TEAM_ID` -- code signing (also hardcoded in ExportOptions plists)
- `APP_ID` -- App Store Connect app identifier
- `BUNDLE_ID` -- iOS bundle identifier

Additional secrets not in `.env` but used elsewhere:
- `SERVER_SECRET` -- key-server auth (Wrangler secret)
- `UNISWAP_API_KEY`, `ETHERSCAN_API_KEY` -- key-server DeFi proxy (optional)
- Device UUIDs -- hardcoded in various scripts and CLAUDE.md

### Design

**`.env.json.example`** (checked into repo, template with empty values):

```json
{
  "app_store_connect": {
    "key_id": "",
    "issuer_id": "",
    "key_file": "private_keys/AuthKey_XXXXXXXX.p8"
  },
  "apple": {
    "team_id": "",
    "bundle_id": "xyz.atsignhandle.cb-mpc",
    "app_id": ""
  },
  "devices": [
    {"name": "iPhone 14 Pro", "udid": ""},
    {"name": "iPhone 15 Pro Max", "udid": ""},
    {"name": "iPhone 17 Pro Max", "udid": ""},
    {"name": "iPad", "udid": ""},
    {"name": "iPhone 13 Mini Red", "udid": ""}
  ],
  "key_server": {
    "url": "https://cb-mpc-key-server.atsignhandle.workers.dev",
    "account_id": "",
    "server_secret": "",
    "uniswap_api_key": "",
    "etherscan_api_key": ""
  },
  "icon": {
    "source_dir": "",
    "fallback_cache": "CBMPCNative/CBMPCNative/Assets.xcassets/AppIcon.appiconset/cache/"
  }
}
```

**`.env.json`** (gitignored, created by developer with real values).

**`scripts/env-helper.sh`** -- sourced by all scripts:

```bash
#!/usr/bin/env bash
# scripts/env-helper.sh
# Reads .env.json and exports shell variables for build scripts.
# Usage: source scripts/env-helper.sh

ENV_JSON="${ENV_JSON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env.json}"

if [ ! -f "$ENV_JSON" ]; then
  echo "ERROR: .env.json not found at $ENV_JSON"
  echo "Copy .env.json.example to .env.json and fill in your values."
  exit 1
fi

# Export ASC variables (used by release.sh, build-changelog.sh, asc-metadata.sh)
# Use /usr/bin/python3 explicitly (ships with macOS, no brew dependency)
_read_json() { /usr/bin/python3 -c "import json,sys; print(json.load(open('$ENV_JSON'))$1)"; }

export ASC_KEY_ID=$(_read_json "['app_store_connect']['key_id']")
export ASC_ISSUER_ID=$(_read_json "['app_store_connect']['issuer_id']")
export ASC_KEY_FILE=$(_read_json "['app_store_connect']['key_file']")
export APPLE_STORE_TEAM_ID=$(_read_json "['apple']['team_id']")
export APP_ID=$(_read_json "['apple']['app_id']")
export BUNDLE_ID=$(_read_json "['apple']['bundle_id']")
```

### Script Migration

All 3 scripts (`release.sh`, `build-changelog.sh`, `asc-metadata.sh`) currently have:
```bash
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a; source "$PROJECT_DIR/.env"; set +a
fi
```

Replace with:
```bash
source "$(dirname "$0")/env-helper.sh"
```

Old `.env` file gets deleted after migration.

---

## 3. Icon Cache for Offline Builds

### Problem

`generate-app-icon.sh` reads cat images from `/Users/mark.phillips/Pictures/compuglobalhypermegacorp/pwa/`. On evm's machine this path doesn't exist.

### Design

Pre-generate 10 icon variants (1024x1024 PNG) and store in:
```
CBMPCNative/CBMPCNative/Assets.xcassets/AppIcon.appiconset/cache/
  icon-build-01.png
  icon-build-02.png
  ...
  icon-build-10.png
  cache-manifest.json
```

**`cache-manifest.json`**:
```json
{
  "description": "Fallback app icons for builds on machines without source cat images",
  "icons": [
    {"file": "icon-build-01.png", "label": "Party Cat 1"},
    {"file": "icon-build-02.png", "label": "Party Cat 2"},
    {"file": "icon-build-03.png", "label": "Party Cat 3"},
    {"file": "icon-build-04.png", "label": "Party Cat 4"},
    {"file": "icon-build-05.png", "label": "Party Cat 5"},
    {"file": "icon-build-06.png", "label": "Party Cat 6"},
    {"file": "icon-build-07.png", "label": "Party Cat 7"},
    {"file": "icon-build-08.png", "label": "Party Cat 8"},
    {"file": "icon-build-09.png", "label": "Party Cat 9"},
    {"file": "icon-build-10.png", "label": "Party Cat 10"}
  ]
}
```

**`generate-app-icon.sh` update**: Check `.env.json` `icon.source_dir` first. If that dir doesn't exist or is empty, read `.env.json` `icon.fallback_cache` and select icon via `build_number % 10`.

---

## 4. README.md Rewrite

### Structure

```markdown
# CB-MPC

Threshold MPC key management for iOS and macOS. Your private key never exists in one place.

## Overview
- What cb-mpc does (1 paragraph)
- Link to visual guides: docs/visual-guide/index.html
- Link to upstream C++ library documentation

## Quick Start (Simulator)
1. Clone the repo
2. Copy .env.json.example -> .env.json, fill in values
3. Place AuthKey .p8 in private_keys/
4. Open CBMPCNative.xcodeproj in Xcode
5. Select iPhone 16 Pro simulator, build and run
6. Verify: app launches, demo keys visible

## Build for Device
1. Connect device via USB
2. List devices: xcrun devicectl list devices
3. Add device UDID to .env.json
4. Build: xcodebuild -sdk iphoneos ... -allowProvisioningUpdates build
5. Install: xcrun devicectl device install app --device <UDID> <app-path>
6. Launch: xcrun devicectl device process launch --device <UDID> xyz.atsignhandle.cb-mpc

## Build for TestFlight
1. Bump version: edit MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.pbxproj
2. Generate changelog: ./scripts/release.sh changelog
3. Review and approve: ./scripts/release.sh approve
4. Archive and upload: ./scripts/release.sh archive && ./scripts/release.sh upload
5. Check status: ./scripts/release.sh status

## Architecture
SwiftUI App -> Swift Wrappers -> Bridging Header -> C API (cbmpc_ios.h)
  -> libcbmpc.a (C++) -> OpenSSL 3.2.0 (custom) + secp256k1

## Project Structure
CBMPCNative/           -- iOS/macOS SwiftUI app
  Models/              -- Crypto engine, coordinators, services
  Views/               -- UI screens and components
key-server/            -- Cloudflare Workers key server (Durable Objects)
src/                   -- C++ MPC library source
cbmpc.xcframework/     -- Pre-built iOS static library
docs/                  -- Documentation and visual guides
scripts/               -- Build, release, and utility scripts

## Documentation
- [Build & Release Workflow](docs/BUILD_AND_RELEASE.md)
- [Feature Roadmap](TODO.md)
- [Visual Guides](docs/visual-guide/index.html)
- [Cryptographic Specs](docs/spec/)
- [Theory Papers](docs/theory/)

## Adding a New Device
1. Connect device, run: xcrun devicectl list devices
2. Copy UDID
3. Add to .env.json devices array
4. Register in Apple Developer portal (automatic with -allowProvisioningUpdates)

## App Icon
Icons are auto-generated from cat images by CBMPCNative/scripts/generate-app-icon.sh.
If source images aren't available, cached icons in Assets.xcassets/AppIcon.appiconset/cache/ are used.
See .env.json icon.source_dir and icon.fallback_cache.
```

---

## 5. CLAUDE.md Expansion

Add these sections to the existing CLAUDE.md:

### After Cloning

```markdown
## After Cloning

1. Copy `.env.json.example` to `.env.json`
2. Fill in all values (get from team lead or 1Password)
3. Place `AuthKey_67F836A739.p8` in `private_keys/`
4. Verify setup: build for simulator
   ```
   xcodebuild -project CBMPCNative/CBMPCNative.xcodeproj \
     -scheme CBMPCNative \
     -sdk iphonesimulator \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
     build
   ```
5. If build succeeds, you're ready to develop

## Common Tasks

| Task | Command |
|------|---------|
| Build simulator | `xcodebuild -scheme CBMPCNative -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` |
| Build device | `xcodebuild -scheme CBMPCNative -sdk iphoneos -configuration Release -destination 'generic/platform=iOS' -allowProvisioningUpdates build` |
| Install to device | `xcrun devicectl device install app --device <UDID> <path-to-.app>` |
| Run tests | `xcodebuild test -scheme CBMPCNativeTests -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` |
| Archive for TF | `./scripts/release.sh archive` |
| Upload to TF | `./scripts/release.sh upload` |
| Bump version | Edit `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in project.pbxproj |
| Generate changelog | `./scripts/release.sh changelog` |

## Key Files to Modify

| Change | Files |
|--------|-------|
| New Swift view | `CBMPCNative/Views/NewView.swift`, update `App.swift` navigation |
| New C API function | `src/cbmpc/ios/cbmpc_ios.h`, implement in `cbmpc_ios.cpp` or `cbmpc_ios_hd.cpp`, rebuild xcframework |
| Version bump | `CBMPCNative.xcodeproj/project.pbxproj` (MARKETING_VERSION, CURRENT_PROJECT_VERSION) |
| New model | `CBMPCNative/Models/NewModel.swift` |

## Known Issues

- **CryptoKit SealedBox crash**: Never use `sealedBox.ciphertext + sealedBox.tag` with Data subscripting. Use `var d = Data(sealedBox.ciphertext); d.append(contentsOf: sealedBox.tag)` instead.
- **bn_t::from_bin()**: This is a STATIC method. Must capture the return value: `auto n = bn_t::from_bin(buf)`.
- **Curve code 714**: Always means secp256k1 in this codebase.
- **Compressed public keys**: Use 33-byte SEC1 compressed format. Use `to_compressed_oct()` not `coinbase::ser()`.
```

---

## 6. AGENTS.md

New file at repo root for AI agents:

```markdown
# AGENTS.md -- AI Agent Orientation Guide

## What This Project Is

CB-MPC is a threshold MPC (Multi-Party Computation) key management app for iOS/macOS.
The private key never exists in one place -- it's split between parties (device + device,
or device + server) using cryptographic protocols.

## Architecture

```
SwiftUI App (CBMPCNative/)
  |
  v
Swift Wrappers (Models/*.swift)
  |
  v
C Bridging Header (CBMPCNative-Bridging-Header.h)
  |
  v
C API (cbmpc.xcframework/Headers/cbmpc_ios.h)
  |
  v
C++ MPC Library (src/cbmpc/) -> OpenSSL 3.2.0 + secp256k1
```

## Key Directories

| Path | Contents |
|------|----------|
| `CBMPCNative/CBMPCNative/Models/` | 41 Swift files: crypto engine, coordinators, services |
| `CBMPCNative/CBMPCNative/Views/` | 31 Swift views: dashboard, demos, signing, pairing |
| `cbmpc.xcframework/` | Pre-built static library for iOS arm64 + simulator |
| `key-server/` | Cloudflare Workers key server (Durable Objects) |
| `scripts/` | Build, release, changelog, metadata scripts |
| `docs/visual-guide/` | 12 HTML interactive visual guides |

## Build Verification

After any code change, verify it compiles:
```bash
xcodebuild -project CBMPCNative/CBMPCNative.xcodeproj \
  -scheme CBMPCNative \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | tail -5
```
Look for `** BUILD SUCCEEDED **`.

## Configuration

All secrets and config are in `.env.json` (see `.env.json.example` for structure).
Scripts source `scripts/env-helper.sh` which reads from `.env.json`.

## Gotchas

1. **CryptoKit SealedBox**: Never concatenate `.ciphertext + .tag` then subscript. Internal slices have non-zero startIndex that crashes in Release builds.
2. **bn_t::from_bin()**: Static method, must capture return: `auto n = bn_t::from_bin(buf)`.
3. **Curve code 714**: secp256k1 everywhere in this codebase.
4. **Public keys**: Always 33-byte compressed SEC1. Use `to_compressed_oct()`.
5. **QR codes**: Binary frames are base64-encoded before QR generation. Max 450 bytes per frame.
6. **Data safety**: Never use `subdata` + `withUnsafeBytes` + `load(as:)` for integer parsing. Use manual byte reads.

## Common Agent Tasks

### Adding a new view
1. Create `CBMPCNative/CBMPCNative/Views/NewView.swift`
2. Add navigation entry in `App.swift` or relevant tab
3. Build for simulator to verify

### Adding a C API function
1. Declare in `cbmpc.xcframework/Headers/cbmpc_ios.h`
2. Implement in `src/cbmpc/ios/cbmpc_ios.cpp` (or `cbmpc_ios_hd.cpp` for HD operations)
3. Rebuild xcframework (requires C++ toolchain)
4. Call from Swift via bridging header

### Bumping version
Edit `CBMPCNative/CBMPCNative.xcodeproj/project.pbxproj`:
- `MARKETING_VERSION` = semver (e.g., "0.25.0")
- `CURRENT_PROJECT_VERSION` = incrementing integer (e.g., 77)
```

---

## 7. TODO.md Feature Roadmap

New file at repo root. Comprehensive status of completed work and prioritized future features.

### Structure

```markdown
# CB-MPC Feature Roadmap

## Completed

### Foundation (v0.1 - v0.6)
- [x] C++ MPC library compiled to xcframework (iOS arm64 + simulator)
- [x] C API bridging layer (cbmpc_ios.h) with 40+ exposed functions
- [x] SwiftUI app scaffold with TabView navigation
- [x] CoreData models and persistence layer
- [x] Platform-aware navigation (iPhone TabView, iPad SplitView, macOS Window)
- [x] Key dashboard with compact list view
- [x] Key detail view with operations and signing UI
- [x] Create new key sheet with key type selection
- [x] Signing history view
- [x] Settings view with Face ID toggle
- [x] Demo data seeding for initial exploration

### Crypto Integration (v0.7 - v0.14)
- [x] ECDSA 2-party key generation and signing (secp256k1)
- [x] N-Party ECDSA and EdDSA C++ FFI and Swift demo views
- [x] ZK proof verification via opaque handle API
- [x] HD key derivation demo
- [x] Key lifecycle demo (generate, refresh, sign, verify)
- [x] Batch signing demo
- [x] Access structure demo
- [x] Agree random demo
- [x] Real demo keys (not mock data)
- [x] Face ID / biometric lock
- [x] Keystore export functionality

### QR and Transport (v0.14 - v0.16)
- [x] QR code generation and display
- [x] QR code scanning via AVCaptureMetadataOutput
- [x] Multi-part QR export/import with base64-encoded binary frames (450-byte limit)
- [x] Network tab with device discovery
- [x] Device pairing via MultipeerConnectivity (Bonjour _cbmpc._tcp)
- [x] 6-tab navigation layout
- [x] Etherscan v2 API integration (balance, transactions)

### Server Integration (v0.16 - v0.18)
- [x] Key server on Cloudflare Workers with Durable Objects
  - DeviceRegistry, DKGSession, KeyVault, SignSession
- [x] Server API client with JWT auth and WebSocket transport
- [x] Server registration view with QR-based pairing
- [x] Server DKG coordinator (device + server key generation)
- [x] Peer DKG coordinator (device-to-device key generation)
- [x] Signing coordinator for unified 2-party signing (device-device and device-server)
- [x] Transport origin UI (dynamic custody badges)
- [x] Co-signer reference storage
- [x] DeviceInfo helper for hardware identification
- [x] Privacy policy endpoint on key server

### Ceremony and Testing (v0.18 - v0.22)
- [x] CeremonySession and KeyShare data structures
- [x] CeremonyCoordinator state machine (initialized -> committed -> signed -> complete)
- [x] KeyShareManager for Keychain storage with SecureEnclave protection
- [x] CeremonyView UI for real-time ceremony progress
- [x] DeviceDeviceDKGCoordinator wrapping peer DKG with ceremony lifecycle
- [x] Ceremony-tracked DKG in ServerDKGCoordinator
- [x] SigningCoordinator for 2-party signing ceremonies
- [x] E2E integration test scaffolds for DKG and signing
- [x] Unit test target (CBMPCNativeTests) with comprehensive coverage
- [x] Shared Xcode schemes for CI builds

### App Store and Release (v0.22 - v0.24)
- [x] App Store Connect automation (metadata push, screenshot upload)
- [x] TestFlight build pipeline via release.sh
- [x] Changelog generation with git tag integration
- [x] 12 HTML interactive visual guide pages
- [x] HD key operations in C API (cbmpc_ios_hd.cpp)
- [x] macOS target support
- [x] App icon generation with party cat themes

### Services (models created, integration pending)
- [x] EIP-712 typed data signer (EIP712Signer.swift)
- [x] Safe multisig service (SafeService.swift)
- [x] Uniswap service (UniswapService.swift)
- [x] Cow Protocol service (CowService.swift)
- [x] Contract ABI service (ContractService.swift)
- [x] Address book (AddressBook.swift)
- [x] Transactions tab view (TransactionsTabView.swift)

---

## Priorities (Future Work)

### P1: Core Wallet Features

1. **Simple Private Key Management**
   - Import/export raw private keys (hex, WIF formats)
   - Display private key with copy-to-clipboard
   - Basic single-key ECDSA signing (no MPC)
   - Clear UI distinction between MPC keys and simple keys

2. **Seed Phrase (BIP-39)**
   - Generate 12/24-word mnemonic from entropy
   - Display word grid with copy functionality
   - Verify backup: user re-enters words in order
   - Derive private key from mnemonic + optional passphrase
   - BIP-44 derivation path display

3. **Shamir Secret Sharing**
   - Split private key into N shares with K-of-N threshold
   - Visual share management (cards showing share index, holder)
   - Reconstruct key from K shares
   - Export individual shares via QR or file
   - Access structure visualization

### P2: MPC Production

4. **MPC 2-Party Key (Production Quality)**
   - Move from local simulation to real 2-party protocol over network
   - Key share location indicators ("Your share: This Device", "Counterparty: Server/Peer")
   - Key health dashboard: last refresh, backup status, counterparty status
   - Key refresh protocol (re-share without changing public key)

5. **MultipeerConnectivity Polish**
   - Reliable peer discovery with retry logic
   - Session recovery after disconnect
   - Multi-round MPC protocol over Bluetooth/WiFi Direct
   - Visual connection quality indicators
   - Support for N>2 party configurations

6. **Commitment Server Integration**
   - Full round-trip DKG with Cloudflare Worker commitment server
   - Persistent session management
   - Server health monitoring from app
   - Automatic reconnection with exponential backoff

7. **Key Server Production Deployment**
   - Deploy key server to production Cloudflare Workers
   - Real DKG + signing with server as Party 1
   - Key refresh via server
   - Server-side key share audit logging

### P3: Transaction Features

8. **ETH Transfer from Device**
   - Originate ETH transfer transactions
   - Gas estimation (EIP-1559 base + priority fee)
   - Transaction signing via 2-party MPC
   - Broadcast to Ethereum network
   - Confirmation tracking with block explorer links
   - Transaction history view

9. **Bitcoin Wallet**
   - BIP-44 derivation for Bitcoin (m/44'/0'/0')
   - Bitcoin address generation (P2PKH, P2WPKH, P2TR)
   - UTXO tracking via Blockstream/Mempool API
   - Transaction construction and signing
   - Fee estimation

### P4: Key Safety

10. **USB-C Key Backup**
    - Export encrypted key shares to external USB-C drive
    - AES-256-GCM encryption with device-bound key wrapping
    - Backup verification screen with integrity checks
    - Restore flow: detect drive, validate backup, import shares
    - Backup manifest with metadata (date, device, key IDs)

11. **Key Location Dashboard**
    - Visual map showing where each share lives (device / server / peer / USB)
    - Health indicators per share (last seen, last refresh, backup age)
    - Alert for shares that haven't been refreshed in >30 days
    - One-tap refresh for stale shares
    - Export/migrate share between storage locations

### P5: DeFi Integration

12. **Uniswap / Cowswap**
    - Token swap interface (select pair, amount, slippage)
    - EIP-712 typed data signing for swap orders
    - Option: sign on device (direct) or via server relay
    - Price quotes from Uniswap v3 / Cow Protocol API
    - Swap execution and confirmation tracking
    - Integration with existing UniswapService and CowService models
```

---

## 8. docs/ Reorganization

### Moves

| Source | Destination | Rationale |
|--------|-------------|-----------|
| `docs/ios/QUICKSTART.md` | `docs/ios/archive/` | C++ build quickstart, not iOS app setup -- archive rather than absorb |
| `docs/ios/*.md` (phase reports) | `docs/ios/archive/` | Historical, not onboarding material |
| `docs/cf-worker/` | Keep as-is | Separate Cloudflare Worker deployment, not part of iOS app |
| `docs/IPHONES.md` | Delete (45 bytes, content in .env.json devices) | Redundant |
| `docs/FEATURE_PLAN.md` | Keep, add note pointing to `TODO.md` | TODO.md is canonical |
| `docs/BUILD_AND_RELEASE.md` | Keep, linked from README | Already comprehensive |
| `docs/visual-guide/` | Keep as-is | No changes needed |
| `docs/iOS-AppStore/` | Keep as-is | Screenshots and changelogs |
| `docs/spec/`, `docs/theory/` | Keep as-is | Cryptographic documentation |

### New Files

| File | Purpose |
|------|---------|
| `README.md` | Rewritten (see Section 4) |
| `CLAUDE.md` | Expanded (see Section 5) |
| `AGENTS.md` | New (see Section 6) |
| `TODO.md` | New (see Section 7) |
| `.env.json.example` | New (see Section 2) |
| `scripts/env-helper.sh` | New (see Section 2) |
| `CBMPCNative/.../cache/` | New icon cache (see Section 3) |

### Deletions

| File | Reason |
|------|--------|
| `.env` | Replaced by `.env.json` |
| `docs/IPHONES.md` | Content moved to .env.json |

---

## Implementation Order

All file changes happen FIRST, then the private repo is created and pushed as the final step.

### Phase A: Secrets and Build Infrastructure
1. Add `.env.json` to `.gitignore`
2. Create `.env.json.example` and `scripts/env-helper.sh` (use `/usr/bin/python3` for macOS compatibility)
3. Create `scripts/validate-env.sh` to check all required keys are non-empty
4. Update `release.sh`, `build-changelog.sh`, `asc-metadata.sh` to source `env-helper.sh`
   - Note: `asc-metadata.sh` currently silently continues if `.env` missing; `env-helper.sh` exits with error. Verify this is acceptable (it should be -- scripts should fail loud if secrets are missing).
5. Create `.env.json` with real values, delete `.env`
6. Test all scripts work: `./scripts/validate-env.sh && ./scripts/release.sh status`

### Phase B: Icon Cache
7. Generate icon cache (10 icons from cat source images)
8. Update `CBMPCNative/CBMPCNative/scripts/generate-app-icon.sh` with fallback logic (note: script lives in `CBMPCNative/scripts/`, not `scripts/`)

### Phase C: Documentation
9. Write `README.md` (include .p8 key file instructions in Quick Start, not just CLAUDE.md)
10. Expand `CLAUDE.md` with post-clone setup
11. Write `AGENTS.md`
12. Write `TODO.md`
13. Reorganize `docs/ios/` (move phase reports to `docs/ios/archive/`)
14. Add note to `docs/FEATURE_PLAN.md` pointing to `TODO.md` as canonical

### Phase D: Build Verification
15. Build for simulator to verify nothing is broken
16. Commit all changes

### Phase E: Private Repo and Branch Cleanup
17. Rename `ios-integration-phase-1` to `ios-macosx-swift-build`
18. Create private repo `tankbottoms/cb-mpc-ios`
19. Push `ios` and `ios-macosx-swift-build` to private repo
20. Set `ios` as default branch on private repo
21. Delete stale branches on public fork (`ios-integration-scratch`, `exp-api`, `network-null-check`)
22. Delete `ios-integration-phase-1` on public fork (after renaming)
23. Clean up local tracking refs: `git fetch --prune`
