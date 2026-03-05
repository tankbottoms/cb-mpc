# CB-MPC iOS Integration

## Overview

Native iOS application (`CBMPCNative`) providing threshold cryptography operations via the cb-mpc C++ library. The app exposes ECDSA 2-party key generation, signing, and HD key derivation through a SwiftUI interface.

## Architecture

```
CBMPCNative (SwiftUI App)
    |
    v
CBMPCNative-Bridging-Header.h
    |
    v
cbmpc_ios.h (C API)
    |
    v
cbmpc.xcframework (static libs)
    |
    +-- ios-arm64/libcbmpc.a (device)
    +-- ios-arm64-simulator/libcbmpc.a (simulator)
    |
    v
OpenSSL 3.2.0 (static libs)
    +-- openssl-ios/ios-arm64/ (device)
    +-- openssl-ios/iossimulator-arm64/ (simulator)
```

## Directory Structure

```
cb-mpc/
  CBMPCNative/                    # Xcode project
    CBMPCNative/
      Models/                     # Swift models, crypto engine, key store
      Views/                      # SwiftUI views
      Navigation/                 # App navigation
      Networking/                 # Signing server client
    docs/                         # Device setup, env setup guides
    build-device.sh               # Build for physical device
    install-device.sh             # Install on connected device
    install-all-devices.sh        # Install on all detected devices
  cbmpc.xcframework/              # Universal static framework
  openssl-ios/                    # Pre-built OpenSSL for iOS
  src/cbmpc/ios/                  # C FFI bridge layer
  scripts/openssl/                # OpenSSL build scripts
```

## Quick Start

### Prerequisites

- Xcode 15+ with iOS 17.0+ SDK
- Apple Development certificate and team (YT6VJY3L35)
- Pre-built OpenSSL libraries (included in `openssl-ios/`)

### Build for Simulator

```bash
# Build libcbmpc.a
cmake -B build/ios-simulator \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=$(xcrun --sdk iphonesimulator --show-sdk-path) \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTS=OFF \
  -DCBMPC_OPENSSL_ROOT="$(pwd)/openssl-ios/iossimulator-arm64"
cmake --build build/ios-simulator -- -j$(sysctl -n hw.ncpu)

# Build XCFramework (if needed)
xcodebuild -create-xcframework \
  -library lib/Release/iOS-arm64/libcbmpc.a -headers /tmp/cbmpc-headers \
  -library lib/Release/libcbmpc.a -headers /tmp/cbmpc-headers \
  -output cbmpc.xcframework

# Build app
xcodebuild build \
  -project CBMPCNative/CBMPCNative.xcodeproj \
  -scheme CBMPCNative \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -configuration Debug
```

### Build for Device

```bash
# Build libcbmpc.a for device
cmake -B build/ios-device \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTS=OFF \
  -DCBMPC_OPENSSL_ROOT="$(pwd)/openssl-ios/ios-arm64"
cmake --build build/ios-device -- -j$(sysctl -n hw.ncpu)

# Build and sign app
xcodebuild build \
  -project CBMPCNative/CBMPCNative.xcodeproj \
  -scheme CBMPCNative \
  -destination "generic/platform=iOS" \
  -configuration Release \
  -allowProvisioningUpdates \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM="YT6VJY3L35"

# Or use the convenience script:
bash CBMPCNative/build-device.sh
```

### Deploy to Device

```bash
bash CBMPCNative/install-device.sh          # Single connected device
bash CBMPCNative/install-all-devices.sh     # All detected devices
```

## C API Layer

The FFI bridge in `src/cbmpc/ios/` exposes these operations:

| File | Operations |
|------|-----------|
| `cbmpc_ios_ecdsa2p.cpp` | 2-party ECDSA key generation and signing |
| `cbmpc_ios_hd.cpp` | HD key derivation (BIP-32) |
| `cbmpc_ios_mem.cpp` | Memory management for C-Swift bridge |
| `cbmpc_ios_network.cpp` | Network transport layer |

## Branch Strategy

- **`master`**: C++/Go library only. No iOS artifacts.
- **`ios`**: Full iOS integration (this branch). Includes pre-built binaries, XCFramework, and CBMPCNative app.

## Rebuilding OpenSSL from Source

If you need to rebuild OpenSSL for iOS:

```bash
bash scripts/openssl/build-static-openssl-ios-arm64.sh          # Device
bash scripts/openssl/build-static-openssl-ios-simulator-arm64.sh # Simulator
bash scripts/openssl/verify-ios-openssl.sh .                     # Verify
```
