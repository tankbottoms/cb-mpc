# CB-MPC

Threshold MPC key management for iOS and macOS. Your private key never exists in one place -- it's split between parties (device + device, or device + server) using multi-party computation protocols.

Built on [Coinbase's cb-mpc](https://github.com/coinbase/cb-mpc) C++ library, compiled to a native iOS xcframework.

## Visual Guides

Interactive HTML visual guides are in [`docs/visual-guide/`](docs/visual-guide/index.html):

- [DKG Ceremony](docs/visual-guide/dkg-ceremony.html) -- How distributed key generation works
- [Signing Operations](docs/visual-guide/signing-operations.html) -- Transaction signing flow
- [Threshold Signing](docs/visual-guide/threshold-signing.html) -- T-of-N threshold schemes
- [Device-to-Device](docs/visual-guide/device-to-device.html) -- Peer-to-peer MPC protocols
- [Server Architecture](docs/visual-guide/server-architecture.html) -- Key server design
- [Key Management](docs/visual-guide/key-management.html) -- Key lifecycle overview
- [Shamir Splitting](docs/visual-guide/shamir-splitting.html) -- Secret sharing schemes
- [Backup & Recovery](docs/visual-guide/backup-recovery-strategies.html) -- Key backup strategies
- [Key Storage Hierarchy](docs/visual-guide/key-storage-hierarchy.html) -- Storage layer design
- [QR Transfer](docs/visual-guide/qr-transfer-workflow.html) -- QR-based key transfer
- [Bluetooth/Multipeer](docs/visual-guide/bluetooth-multipeer-protocol.html) -- Peer discovery
- [Custody Models](docs/visual-guide/custody-models.html) -- Self vs shared custody
- [iOS Encryption](docs/visual-guide/ios-encryption-backup-strategy.html) -- iOS-specific encryption

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Xcode | 16+ | Mac App Store |
| Xcode Command Line Tools | latest | `xcode-select --install` |
| Python 3 | 3.9+ | Ships with macOS (`/usr/bin/python3`) |
| ImageMagick | 7+ | `brew install imagemagick` (icon generation only) |
| gh CLI | latest | `brew install gh` (GitHub operations only) |

## First Time Setup: Register Your Device

**Do this before building for a physical device.** Connect your iPhone/iPad via USB-C and run:

```bash
./scripts/add-device.sh
```

The script will:
1. List all connected devices with their UDIDs
2. Prompt you to paste the UDID and give the device a name
3. Add it to `.env.json` so all scripts know about it
4. Print the exact build, install, and launch commands for your device

The first build with `-allowProvisioningUpdates` automatically registers the device with the Apple Developer portal -- no manual portal setup needed.

**Already-registered devices** (in `.env.json`):

| Device | UDID |
|--------|------|
| iPhone 14 Pro | `5645DF68-EB3D-5845-9DE9-47305629646A` |
| iPhone 15 Pro Max | `315E4279-EB38-578C-8375-63AC801B0200` |
| iPhone 17 Pro Max | `06A0A98A-72FD-5A20-B13C-F8BD32FC55F0` |
| iPad | `00008101-000A288E2252601E` |
| iPhone 13 Mini Red | `2DCF8B6B-7136-5339-BC7F-56266D69C2BC` |

---

## Quick Start (Simulator)

```bash
# 1. Clone
git clone git@tankbottoms.github.com:tankbottoms/cb-mpc-ios.git
cd cb-mpc-ios

# 2. Verify config
#    .env.json and private_keys/ are included in the repo.
./scripts/validate-env.sh

# 3. Build for simulator
xcodebuild -project CBMPCNative/CBMPCNative.xcodeproj \
  -scheme CBMPCNative \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# 4. Or open in Xcode
open CBMPCNative/CBMPCNative.xcodeproj
# Select "iPhone 17 Pro" simulator, click Run
```

## Build for Device

```bash
# 1. Connect device via USB-C and register it (if not already done)
./scripts/add-device.sh

# 2. Build for device
xcodebuild -project CBMPCNative/CBMPCNative.xcodeproj \
  -scheme CBMPCNative \
  -sdk iphoneos \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build

# 3. Find the .app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/CBMPCNative-*/Build/Products/Release-iphoneos -name "CBMPCNative.app" -maxdepth 1 | head -1)

# 4. Install to device (replace DEVICE_UDID with yours -- add-device.sh prints this)
xcrun devicectl device install app --device DEVICE_UDID "$APP_PATH"

# 5. Launch
xcrun devicectl device process launch --device DEVICE_UDID xyz.atsignhandle.cb-mpc
```

## Build for TestFlight

```bash
# 1. Bump version (patch/minor/major)
./scripts/release.sh prepare minor

# 2. Review the generated changelog
./scripts/release.sh approve

# 3. Archive for distribution
./scripts/release.sh build

# 4. Upload to TestFlight and push metadata
./scripts/release.sh submit

# 5. Check processing status
./scripts/release.sh status
```

See [`docs/BUILD_AND_RELEASE.md`](docs/BUILD_AND_RELEASE.md) for the full workflow.

## Architecture

```
SwiftUI App (CBMPCNative/)
  |
  v
Swift Wrappers (Models/*.swift)
  |  CBMPCCryptoEngine, CBMPCKeyShare, CBMPCSigner, etc.
  v
C Bridging Header (CBMPCNative-Bridging-Header.h)
  |
  v
C API (cbmpc.xcframework/Headers/cbmpc_ios.h)
  |  40+ exposed functions for keygen, signing, HD derivation, ZK proofs
  v
C++ MPC Library (src/cbmpc/)
  |  Threshold ECDSA, EdDSA, Shamir sharing, commitment schemes
  v
OpenSSL 3.2.0 (custom) + libsecp256k1
```

## Project Structure

```
CBMPCNative/                -- iOS/macOS SwiftUI application
  CBMPCNative/
    Models/                 -- 41 Swift files: crypto engine, coordinators, services
    Views/                  -- 31 Swift views: dashboard, demos, signing, pairing
    Navigation/             -- App navigation (TabView, SplitView)
    Assets.xcassets/        -- App icons, colors
  CBMPCNativeTests/         -- Unit and integration tests
  scripts/                  -- Icon generation
cbmpc.xcframework/          -- Pre-built iOS static library (arm64 + simulator)
key-server/                 -- Cloudflare Workers key server (Durable Objects)
  src/                      -- TypeScript: DKG, signing, device registry, key vault
scripts/                    -- Build, release, changelog, metadata, env scripts
  release.sh                -- Full release lifecycle orchestrator
  build-changelog.sh        -- Changelog generation and ASC push
  asc-metadata.sh           -- App Store Connect metadata upload
  env-helper.sh             -- Reads .env.json, exports shell variables
  validate-env.sh           -- Validates .env.json has required values
docs/
  BUILD_AND_RELEASE.md      -- Detailed release workflow
  visual-guide/             -- 12+ interactive HTML visual guides
  iOS-AppStore/             -- Screenshots, changelogs, metadata
  spec/                     -- Cryptographic protocol specifications
  theory/                   -- Theoretical documentation
  FEATURE_PLAN.md           -- Detailed UI/UX feature plan
src/                        -- C++ MPC library source (shared)
  cbmpc/ios/                -- iOS-specific C API implementation
```

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/release.sh` | Full release lifecycle: bump, changelog, archive, upload, status |
| `scripts/build-changelog.sh` | Generate changelogs, tag builds, push "What to Test" to ASC |
| `scripts/asc-metadata.sh` | Upload metadata to App Store Connect |
| `scripts/add-device.sh` | Register a new iOS device: reads UDID, adds to .env.json, prints build commands |
| `scripts/validate-env.sh` | Verify .env.json is complete and .p8 key file exists |
| `scripts/env-helper.sh` | Reads .env.json, exports shell vars (sourced by other scripts) |
| `CBMPCNative/scripts/generate-app-icon.sh` | Generate app icon from layered cat images |

## App Icon

Icons are auto-generated from layered cat images by `CBMPCNative/scripts/generate-app-icon.sh` using ImageMagick. If the source image directory isn't available on your machine, the current icon (`AppIcon-1024.png`) is checked in and works as-is. Pre-cached fallback icons are in the `cache/` directory.

## Working with Claude Code

This repo includes [`CLAUDE.md`](CLAUDE.md) and [`AGENTS.md`](AGENTS.md) for AI-assisted development:

```bash
cd cb-mpc-ios
claude
```

Claude reads `CLAUDE.md` automatically for build conventions, known issues, and common tasks. `AGENTS.md` provides architectural context and gotchas.

## Feature Roadmap

See [`TODO.md`](TODO.md) for completed features (v0.1-v0.24) and prioritized future work.

## Documentation

| Document | Contents |
|----------|----------|
| [Build & Release](docs/BUILD_AND_RELEASE.md) | Commit-to-TestFlight pipeline |
| [Feature Plan](docs/FEATURE_PLAN.md) | Detailed UI/UX implementation plan |
| [Visual Guides](docs/visual-guide/) | Interactive HTML protocol visualizations |
| [Cryptographic Specs](docs/spec/) | Protocol specifications (PDF, git-lfs) |
| [Theory Papers](docs/theory/) | Theoretical foundations (PDF, git-lfs) |
| [Key Generation Analysis](docs/KEY_GENERATION_ANALYSIS.md) | Key generation deep dive |
| [UX Workflows](docs/UX_WORKFLOWS.md) | User experience flow documentation |

## License

Based on [coinbase/cb-mpc](https://github.com/coinbase/cb-mpc). See LICENSE for details.
