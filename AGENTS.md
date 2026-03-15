# AGENTS.md -- AI Agent Orientation Guide

## What This Project Is

CB-MPC is a threshold MPC (Multi-Party Computation) key management app for iOS/macOS. The private key never exists in one place -- it's split between parties (device + device, or device + server) using cryptographic protocols built on Coinbase's cb-mpc C++ library.

## Architecture

```
SwiftUI App (CBMPCNative/)
  |
  v
Swift Wrappers (CBMPCNative/CBMPCNative/Models/*.swift)
  |  CBMPCCryptoEngine -- main crypto interface
  |  CBMPCKeyShare, CBMPCSigner -- key/signing abstractions
  |  ServerDKGCoordinator, PeerDKGCoordinator -- DKG orchestration
  |  SigningCoordinator, PeerSigningCoordinator -- signing orchestration
  |  CeremonyCoordinator -- state machine for MPC ceremonies
  v
C Bridging Header (CBMPCNative-Bridging-Header.h)
  |
  v
C API (cbmpc.xcframework/Headers/cbmpc_ios.h)
  |  40+ functions: keygen, signing, HD derivation, ZK proofs, access structures
  v
C++ MPC Library (src/cbmpc/)
  |  Threshold ECDSA, EdDSA, Shamir sharing, commitment schemes
  v
OpenSSL 3.2.0 (custom build) + libsecp256k1
```

## Key Directories

| Path | Contents |
|------|----------|
| `CBMPCNative/CBMPCNative/Models/` | 41 Swift files: crypto engine, coordinators, transport, services |
| `CBMPCNative/CBMPCNative/Views/` | 31 Swift views: dashboard, demos, signing, pairing, QR, settings |
| `CBMPCNative/CBMPCNative/Navigation/` | AppNavigation.swift -- tab/split routing |
| `CBMPCNative/CBMPCNative/App.swift` | App entry point, scene configuration |
| `cbmpc.xcframework/` | Pre-built static library for iOS arm64 + simulator |
| `cbmpc.xcframework/Headers/cbmpc_ios.h` | C API header -- all exposed functions |
| `key-server/` | Cloudflare Workers key server with Durable Objects |
| `key-server/src/index.ts` | Server routes, auth, Durable Object bindings |
| `key-server/src/types.ts` | TypeScript interfaces for server types |
| `scripts/` | Build, release, changelog, metadata, env scripts |
| `docs/visual-guide/` | 12+ interactive HTML visual guides |
| `docs/FEATURE_PLAN.md` | Detailed 8-phase UI/UX implementation plan |

## Build Verification

After any code change, verify it compiles:

```bash
xcodebuild -project CBMPCNative/CBMPCNative.xcodeproj \
  -scheme CBMPCNative \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | tail -5
```

Look for `** BUILD SUCCEEDED **`.

## Configuration

All secrets and config are in `.env.json` at repo root. Scripts source `scripts/env-helper.sh` which reads from it.

Key values in `.env.json`:
- `app_store_connect` -- ASC API key ID, issuer, .p8 file path
- `apple` -- team ID, bundle ID, app ID
- `devices` -- array of test device UDIDs
- `key_server` -- Cloudflare Worker URL, account ID, secrets
- `icon` -- source image directory, fallback cache path

## Gotchas

1. **CryptoKit SealedBox crash**: Never concatenate `.ciphertext + .tag` then subscript the result. Internal slices have non-zero `startIndex` that crashes in Release builds. Use `var d = Data(sealedBox.ciphertext); d.append(contentsOf: sealedBox.tag)`.

2. **bn_t::from_bin()**: This is a STATIC method in the C++ library. Must capture the return value: `auto n = bn_t::from_bin(buf)`. Calling it without capturing silently discards the result.

3. **Curve code 714**: Always means secp256k1 in this codebase. Passed to C API functions as an integer parameter.

4. **Public keys**: Always 33-byte compressed SEC1 format. Use `to_compressed_oct()` not `coinbase::ser()`.

5. **QR codes**: Binary CBMPC frames are base64-encoded before QR generation. Max 450 bytes per binary frame -> ~600 chars base64 -> QR version 9-10. Scanner reads `stringValue` -> `Data(base64Encoded:)`.

6. **Data subscript safety**: Never use `subdata` + `withUnsafeBytes` + `load(as:)` for integer parsing. Use manual byte reads to avoid alignment and slice-offset crashes.

7. **Key share packing**: Both 2-party key shares are packed as `[4-byte k0 length][k0 bytes][k1 bytes]` and stored in UserDefaults keyed by `key_{UUID}`.

## Common Agent Tasks

### Adding a new view

1. Create `CBMPCNative/CBMPCNative/Views/NewView.swift`
2. Add navigation entry in `App.swift` or the relevant tab in `AppNavigation.swift`
3. Build for simulator to verify

### Adding a C API function

1. Declare in `cbmpc.xcframework/Headers/cbmpc_ios.h`
2. Implement in `src/cbmpc/ios/cbmpc_ios.cpp` (or `cbmpc_ios_hd.cpp` for HD operations)
3. Rebuild xcframework: `cd src/cbmpc/ios && cmake . && make`
4. Call from Swift via the bridging header -- function is automatically available

### Bumping version

Edit `CBMPCNative/CBMPCNative.xcodeproj/project.pbxproj`:
- `MARKETING_VERSION` = semver (e.g., "0.25.0") -- appears in 4 places (2 Debug + 2 Release)
- `CURRENT_PROJECT_VERSION` = incrementing integer (e.g., 77) -- appears in 4 places

Or use the release script: `./scripts/release.sh prepare minor`

### Running tests

```bash
xcodebuild test -project CBMPCNative/CBMPCNative.xcodeproj \
  -scheme CBMPCNativeTests \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Understanding the key server

The key server is a Cloudflare Worker with 4 Durable Objects:
- `DeviceRegistry` -- device registration and auth token management
- `DKGSession` -- distributed key generation session state
- `KeyVault` -- server-side key share storage
- `SignSession` -- signing session coordination

Entry point: `key-server/src/index.ts`. Types: `key-server/src/types.ts`.
Config: `key-server/wrangler.toml`.

### Understanding the visual guides

12+ HTML files in `docs/visual-guide/` explain the cryptographic protocols visually. Start with `index.html` for the overview, then read individual guides for specific protocols. These are the source of truth for how the UX should map to the underlying crypto.

## Important References

| Resource | Location |
|----------|----------|
| Feature roadmap | `TODO.md` (root) |
| Detailed UI/UX plan | `docs/FEATURE_PLAN.md` |
| Build/release workflow | `docs/BUILD_AND_RELEASE.md` |
| Protocol visual guides | `docs/visual-guide/` |
| C API header | `cbmpc.xcframework/Headers/cbmpc_ios.h` |
| Key server types | `key-server/src/types.ts` |
