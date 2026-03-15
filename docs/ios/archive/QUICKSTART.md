# Phase 3 Quick Start — libcbmpc.a Build

**Status:** GREEN - READY TO BUILD
**Time to Complete:** 45-60 minutes
**Blocking Issues:** None

---

## 1. Pre-Build Verification (5 minutes)

Run these commands to verify your environment:

```bash
# Check Xcode
xcode-select -p
# Expected: /Applications/Xcode.app/Contents/Developer

# Check iOS SDKs
xcrun --sdk iphoneos --show-sdk-path
# Expected: Valid path like /Applications/Xcode.app/.../iPhoneOS.sdk

xcrun --sdk iphonesimulator --show-sdk-path
# Expected: Valid path like /Applications/Xcode.app/.../iPhoneSimulator.sdk

# Check CMake
cmake --version
# Expected: cmake version 3.16 or higher
```

If all commands succeed, proceed to Step 2.

---

## 2. Download OpenSSL 3.2.0 (5 minutes)

```bash
cd /Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1

# Download OpenSSL 3.2.0 source
curl -L https://github.com/openssl/openssl/releases/download/openssl-3.2.0/openssl-3.2.0.tar.gz \
  -o openssl-3.2.0.tar.gz

# Extract
tar xzf openssl-3.2.0.tar.gz

# Verify extraction
ls -la openssl-3.2.0/Configure  # Should exist
```

---

## 3. Build OpenSSL for iOS (30 minutes)

```bash
cd /Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1

# All-in-one build (simplest)
bash scripts/openssl/build-ios-fast.sh openssl-3.2.0 openssl-ios

# Verify successful build
bash scripts/openssl/verify-ios-openssl.sh
# Should show all targets verified ✓
```

---

## 4. Build libcbmpc.a for iOS Device (7 minutes)

```bash
cd /Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1

mkdir -p build/ios-arm64
cd build/ios-arm64

cmake -S ../.. -B . \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=$(xcrun --sdk iphoneos --show-sdk-path) \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTS=OFF \
  -DCBMPC_OPENSSL_ROOT="$(pwd)/../../openssl-ios/ios-arm64" \
  -DCMAKE_CXX_COMPILER=$(xcrun --sdk iphoneos --find clang++) \
  -DCMAKE_C_COMPILER=$(xcrun --sdk iphoneos --find clang)

cmake --build . --target cbmpc -j$(sysctl -n hw.ncpu)

# Verify
lipo -info lib/Release/libcbmpc.a
# Expected: Architectures in the fat file: arm64
```

---

## 5. Build libcbmpc.a for iOS Simulator (7 minutes)

In a new terminal window (can run in parallel with Step 4):

```bash
cd /Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1

mkdir -p build/ios-simulator
cd build/ios-simulator

cmake -S ../.. -B . \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_SYSROOT=$(xcrun --sdk iphonesimulator --show-sdk-path) \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTS=OFF \
  -DCBMPC_OPENSSL_ROOT="$(pwd)/../../openssl-ios/iossimulator" \
  -DCMAKE_CXX_COMPILER=$(xcrun --sdk iphonesimulator --find clang++) \
  -DCMAKE_C_COMPILER=$(xcrun --sdk iphonesimulator --find clang)

cmake --build . --target cbmpc -j$(sysctl -n hw.ncpu)

# Verify
lipo -info lib/Release/libcbmpc.a
# Expected: Architectures in the fat file: x86_64 arm64
```

---

## 6. Create XCFramework (2 minutes)

```bash
cd /Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1

xcodebuild -create-xcframework \
  -library build/ios-arm64/lib/Release/libcbmpc.a \
  -headers src/cbmpc/ios/ \
  -library build/ios-simulator/lib/Release/libcbmpc.a \
  -headers src/cbmpc/ios/ \
  -output cbmpc.xcframework

# Verify structure
ls -la cbmpc.xcframework/
# Should contain: ios-arm64, ios-arm64_x86_64-simulator, Info.plist
```

---

## 7. Link in Xcode Project (5 minutes)

```bash
# Copy XCFramework to project
cp -r cbmpc.xcframework CBMPCNative/
```

Then in Xcode:
1. Open CBMPCNative.xcodeproj
2. Select project → CBMPCNative target
3. Go to "General" tab
4. Scroll to "Frameworks, Libraries, and Embedded Content"
5. Click "+" and add cbmpc.xcframework
6. Set to "Embed & Sign"
7. Build project (Product → Build)

---

## Success Checklist

- [ ] Environment verified (Xcode, iOS SDK, CMake)
- [ ] OpenSSL 3.2.0 downloaded and extracted
- [ ] OpenSSL built for iOS (all targets verified)
- [ ] libcbmpc.a built for device (arm64)
- [ ] libcbmpc.a built for simulator (arm64 + x86_64)
- [ ] XCFramework created with correct structure
- [ ] XCFramework copied to CBMPCNative
- [ ] XCFramework linked in Xcode
- [ ] CBMPCNative builds without errors

---

## Troubleshooting

**Problem:** "ios64-xcrun: command not found"
- **Cause:** OpenSSL version too old
- **Solution:** Verify you downloaded 3.2.0 with `tar tzf openssl-3.2.0.tar.gz | head -1`

**Problem:** "Cannot find libcrypto.a"
- **Cause:** OpenSSL build failed
- **Solution:** Run `bash scripts/openssl/verify-ios-openssl.sh` to see which targets failed

**Problem:** CMake configuration fails with "Cannot determine compiler"
- **Cause:** Xcode CLT not installed
- **Solution:** Run `xcode-select --install`

**Problem:** XCFramework creation fails
- **Cause:** One of the libcbmpc.a files is missing
- **Solution:** Verify both files exist:
  ```bash
  file build/ios-arm64/lib/Release/libcbmpc.a
  file build/ios-simulator/lib/Release/libcbmpc.a
  ```

---

## Next Steps

Once XCFramework is linked and project builds successfully:

1. Replace mock signing operations with real C API calls
2. Implement Secure Enclave key generation
3. Add server communication layer
4. Activate iCloud sync

See `/docs/plans/2026-03-02-cbmpc-phase2-real-crypto.md` for details.

---

## Documentation

For more detailed information:

- **Full assessment:** `/BUILD-INFRASTRUCTURE-ASSESSMENT.md`
- **Build strategy:** `/docs/plans/2026-03-02-libcbmpc-build-strategy.md`
- **Troubleshooting:** `/docs/plans/2026-03-02-libcbmpc-build-strategy.md#troubleshooting`

---

**Total Time:** 45-60 minutes (sequential) or 35-45 minutes (with parallelization)
**Status:** GREEN - READY TO BUILD
**Date:** 2026-03-02
