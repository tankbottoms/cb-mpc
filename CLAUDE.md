# cb-mpc Project Instructions

## iOS Build Versioning

Each code revision that changes the iOS app MUST increment the version following semver:

- **Patch** (0.1.x): Bug fixes, minor UI tweaks
- **Minor** (0.x.0): New features, new demo views, new API bindings
- **Major** (x.0.0): Breaking changes, architecture overhauls

The build number (`CFBundleVersion`) MUST increment on every build pushed to device.

Update both values in `CBMPCNative/CBMPCNative.xcodeproj/project.pbxproj`:
- `MARKETING_VERSION` = semver string (e.g., "0.2.0")
- `CURRENT_PROJECT_VERSION` = integer build number (e.g., 7)

The Settings view reads these from `Info.plist` at runtime - do not hardcode version strings in Swift.

## Build Targets

- **Simulator**: `xcodebuild -sdk iphonesimulator -destination 'platform=iOS Simulator,...'`
- **Device**: `xcodebuild -sdk iphoneos -destination 'platform=iOS,id=...' -allowProvisioningUpdates build`
- **Install**: `xcrun devicectl device install app --device <UUID> <app-path>`
- **Launch**: `xcrun devicectl device process launch --device <UUID> xyz.atsignhandle.cb-mpc`

## Architecture

SwiftUI -> Swift Wrappers -> Bridging Header -> C API (`cbmpc_ios.h`) -> libcbmpc.a (C++) -> OpenSSL + secp256k1

Key data is stored in UserDefaults keyed by `key_{UUID}`. Both 2-party key shares are packed as `[4-byte k0 length][k0 bytes][k1 bytes]`.

## Conventions

- Compressed SEC1 public keys (33 bytes for secp256k1)
- Use `to_compressed_oct()` not `coinbase::ser()` for public key extraction
- `bn_t::from_bin()` is STATIC - must capture return value
- Curve code 714 = secp256k1
