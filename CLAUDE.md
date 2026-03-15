# cb-mpc Project Instructions

## After Cloning

1. Run `./scripts/validate-env.sh` to verify `.env.json` and `.p8` key file are present
2. Build for simulator to verify setup:
   ```bash
   xcodebuild -project CBMPCNative/CBMPCNative.xcodeproj \
     -scheme CBMPCNative \
     -sdk iphonesimulator \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     build
   ```
3. If build succeeds, you're ready to develop

## iOS Build Versioning

Each code revision that changes the iOS app MUST increment the version following semver:

- **Patch** (0.1.x): Bug fixes, minor UI tweaks
- **Minor** (0.x.0): New features, new demo views, new API bindings
- **Major** (x.0.0): Breaking changes, architecture overhauls

The build number (`CFBundleVersion`) MUST increment on every build pushed to device or TestFlight.

Update both values in `CBMPCNative/CBMPCNative.xcodeproj/project.pbxproj`:
- `MARKETING_VERSION` = semver string (e.g., "0.25.0")
- `CURRENT_PROJECT_VERSION` = integer build number (e.g., 77)

The Settings view reads these from `Info.plist` at runtime -- do not hardcode version strings in Swift.

## Common Tasks

| Task | Command |
|------|---------|
| Build simulator | `xcodebuild -scheme CBMPCNative -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` |
| Build device | `xcodebuild -project CBMPCNative/CBMPCNative.xcodeproj -scheme CBMPCNative -sdk iphoneos -configuration Release -destination 'generic/platform=iOS' -allowProvisioningUpdates build` |
| Install to device | `xcrun devicectl device install app --device <UDID> <path-to-.app>` |
| Launch on device | `xcrun devicectl device process launch --device <UDID> xyz.atsignhandle.cb-mpc` |
| Run tests | `xcodebuild test -project CBMPCNative/CBMPCNative.xcodeproj -scheme CBMPCNativeTests -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` |
| Bump + changelog | `./scripts/release.sh prepare minor` |
| Archive for TF | `./scripts/release.sh build` |
| Upload to TF | `./scripts/release.sh submit` |
| Check TF status | `./scripts/release.sh status` |
| Validate env | `./scripts/validate-env.sh` |

## Build Targets

- **Simulator**: `-sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- **Device**: `-sdk iphoneos -configuration Release -destination 'generic/platform=iOS' -allowProvisioningUpdates`
- **Install**: `xcrun devicectl device install app --device <UDID> <app-path>`
- **Launch**: `xcrun devicectl device process launch --device <UDID> xyz.atsignhandle.cb-mpc`

## Architecture

```
SwiftUI -> Swift Wrappers -> Bridging Header -> C API (cbmpc_ios.h) -> libcbmpc.a (C++) -> OpenSSL + secp256k1
```

Key data is stored in UserDefaults keyed by `key_{UUID}`. Both 2-party key shares are packed as `[4-byte k0 length][k0 bytes][k1 bytes]`.

## Key Files to Modify

| Change | Files |
|--------|-------|
| New Swift view | `CBMPCNative/CBMPCNative/Views/NewView.swift`, update `App.swift` navigation |
| New C API function | `cbmpc.xcframework/Headers/cbmpc_ios.h`, implement in `src/cbmpc/ios/cbmpc_ios.cpp` or `cbmpc_ios_hd.cpp`, rebuild xcframework |
| Version bump | `CBMPCNative/CBMPCNative.xcodeproj/project.pbxproj` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) |
| New model | `CBMPCNative/CBMPCNative/Models/NewModel.swift` |
| Script config | `.env.json` (all scripts read from here via `scripts/env-helper.sh`) |

## Conventions

- Compressed SEC1 public keys (33 bytes for secp256k1)
- Use `to_compressed_oct()` not `coinbase::ser()` for public key extraction
- `bn_t::from_bin()` is STATIC -- must capture return value: `auto n = bn_t::from_bin(buf)`
- Curve code 714 = secp256k1

## Known Issues

- **CryptoKit SealedBox crash (Release builds)**: Never use `sealedBox.ciphertext + sealedBox.tag` followed by Data subscripting. The `+` operator on CryptoKit slices produces Data with non-zero `startIndex` that crashes in optimized builds. Fix: `var d = Data(sealedBox.ciphertext); d.append(contentsOf: sealedBox.tag)`
- **Data subscript safety**: Never use `subdata` + `withUnsafeBytes` + `load(as:)` for integer parsing. Use manual byte reads (`readUInt16BE` / `readUInt32BE` helpers).
- **QR codes**: Binary CBMPC frames are base64-encoded before QR generation. Max 450 bytes per frame. Scanner reads `stringValue` -> `Data(base64Encoded:)`.

## Secrets and Configuration

All secrets are in `.env.json` at repo root. All build scripts source `scripts/env-helper.sh` which reads from it. Never hardcode secrets in scripts or Swift code.

To add a new secret:
1. Add the field to `.env.json` and `.env.json.example`
2. Add the export line to `scripts/env-helper.sh`
3. Add a check to `scripts/validate-env.sh`
