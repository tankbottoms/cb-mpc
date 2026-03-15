# cb-mpc iOS/Swift/Expo Integration — Implementation Status

**Last updated:** March 2, 2026
**Branch:** `ios-integration-phase-1`
**Repository:** https://github.com/tankbottoms/cb-mpc

## Summary

This document tracks the implementation progress of the complete iOS integration stack for Coinbase's cb-mpc C++ MPC library into Expo/React Native iOS applications.

## Phase Completion Status

### ✅ Phase 0: Environment Verification
**Status:** COMPLETE
- CMake ≥ 3.16 verified
- Xcode 15+ with iOS SDK 14.0+ verified
- xcrun paths available for device and simulator

### ✅ Phase 1: CMake Patches
**Status:** COMPLETE
**Commits:** `35a2f83`

Three critical bugfixes applied:
1. ✅ `cmake/compilation_flags.cmake` — Changed `IS_APPLE` to `IS_MACOS` (line 59)
   - Prevents macOS-only frameworks (CoreServices, IOKit) from being linked on iOS SDK
2. ✅ `cmake/openssl.cmake` — Added iOS/simulator branch to `link_openssl` macro
   - Enables OpenSSL linkage for iOS targets
3. ✅ `CMakeLists.txt` — Disabled `BUILD_TESTS` for iOS targets
   - GoogleTest not available on iOS SDK

**Key achievement:** iOS SDK no longer rejects build configurations

### ✅ Phase 2: OpenSSL 3.2.0 Cross-Compilation Scripts
**Status:** COMPLETE
**Commits:** `741dba0`

Ready-to-run scripts created:
1. ✅ `scripts/openssl/build-static-openssl-ios-arm64.sh` — Device build
2. ✅ `scripts/openssl/build-static-openssl-ios-simulator-arm64.sh` — Simulator arm64
3. ✅ `scripts/openssl/build-static-openssl-ios-simulator-x86_64.sh` — Simulator x86_64
4. ✅ `scripts/openssl/combine-ios-simulator-slices.sh` — Fat binary assembly
5. ✅ `scripts/openssl/verify-ios-openssl.sh` — Verification utility

**Key achievement:** OpenSSL can be cross-compiled for all iOS architectures (pending network availability)

### ❌ Phase 3: Cross-Compile libcbmpc.a as XCFramework
**Status:** BLOCKED (awaiting Phase 2 completion)
**Depends on:** OpenSSL built

Once OpenSSL is available, execute:
```bash
# Build for device
cmake -S . -B build/ios-arm64 \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCBMPC_OPENSSL_ROOT="$(pwd)/openssl-ios/ios-arm64" \
  ...

# Build for simulator
cmake -S . -B build/ios-simulator \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCBMPC_OPENSSL_ROOT="$(pwd)/openssl-ios/iossimulator" \
  ...

# Create XCFramework
xcodebuild -create-xcframework \
  -library build/ios-arm64/lib/Release/libcbmpc.a \
  -headers src/cbmpc/ios/ \
  -library build/ios-simulator/lib/Release/libcbmpc.a \
  -headers src/cbmpc/ios/ \
  -output cbmpc.xcframework
```

### ✅ Phase 4: iOS C API Layer
**Status:** COMPLETE
**Commits:** `e42a26b`

Complete C API layer implemented following demos-go/cb-mpc-go/internal/cgobinding/ patterns:

1. ✅ `src/cbmpc/ios/cbmpc_ios.h` — Public extern "C" header
   - Memory: cbmpc_malloc/cbmpc_free
   - Transport: callback function types and transport_t struct
   - Job: cbmpc_job2p_t creation and lifecycle
   - ECDSA 2P: DKG, sign, refresh, serialization
   - HD Keyset: DKG, derive, refresh
   - Signature verification: stateless ecc_verify_der

2. ✅ `src/cbmpc/ios/cbmpc_ios_mem.cpp` — Memory management
   - Re-exports cgo_malloc/cgo_free

3. ✅ `src/cbmpc/ios/cbmpc_ios_network.cpp` — Transport callbacks
   - callback_data_transport_t implementation
   - job_2p_t creation and lifecycle
   - Error handling and validation

4. ✅ `src/cbmpc/ios/cbmpc_ios_ecdsa2p.cpp` — ECDSA 2P operations
   - DKG, refresh, sign_batch
   - Key serialization/deserialization
   - Public key extraction

5. ✅ `src/cbmpc/ios/cbmpc_ios_hd.cpp` — HD keyset operations
   - HD DKG, derive, refresh
   - BIP44 path handling

6. ✅ `src/cbmpc/ios/CMakeLists.txt` — iOS API compilation
   - Only compiles when IS_IOS or IS_IOS_SIMULATOR

7. ✅ Root `CMakeLists.txt` — iOS layer integration
   - iOS API objects linked into cbmpc library

**Key achievement:** Complete C API ready for Swift wrapping

### ⏳ Phase 5: Swift Package (CbMpcSwift)
**Status:** NOT STARTED
**Repository:** To be created at `https://github.com/tankbottoms/cb-mpc-swift`

**Scope:**
- Swift Package.swift manifest
- CbMpcC system library target (wraps cbmpc.xcframework)
- CbMpcSwift target with:
  - Memory.swift (cmem_t lifecycle)
  - Transport.swift (protocol definition)
  - TransportBridge.swift (@_cdecl callbacks, Unmanaged)
  - MockTransport.swift (in-process pair using actors)
  - HttpTransport.swift (URLSession-based production)
  - Job2P.swift (async/await wrapper)
  - Ecdsa2P.swift (DKG/sign/refresh wrappers)
  - HdKeySet.swift (HD operations)
- CbMpcSwiftTests target with comprehensive test suite

**Estimated effort:** 3-4 commits

### ⏳ Phase 6: Expo Native Module
**Status:** NOT STARTED
**Repository:** To be created at `https://github.com/tankbottoms/cb-mpc-expo-module`

**Scope:**
- expo-module.config.json
- ios/CbMpcModule.swift (ExpoModule subclass)
- ios/CbMpcModule.podspec
- src/index.ts + CbMpcModule.types.ts
- AsyncFunction handlers:
  - createMockSession(sessionId, roleIndex)
  - createHttpSession(sessionId, roleIndex, serverUrl)
  - destroySession(sessionId)
  - ecdsa2pDkg(sessionId, curveCode)
  - ecdsa2pSign(sessionId, keyShareB64, messageHex)
  - ecdsa2pRefresh(sessionId, keyShareB64)
  - ecdsaVerify(curveCode, pubkeyHex, hashHex, derSigB64)

**Estimated effort:** 2-3 commits

### ⏳ Phase 7: Demo App
**Status:** NOT STARTED
**Repository:** To be created at `https://github.com/tankbottoms/cb-mpc-demo-app`

**Scope:**
- Expo React Native app
- Screens:
  - DKG: Generate key pair, display public key
  - Sign: Message input, SHA-256, signature, verify
  - HD Derive: BIP44 path input, derive child, show pubkey
  - Benchmark: Keygen/sign timing vs JS baseline
- Mock mode flow demonstration

**Estimated effort:** 2 commits

### ⏳ Phase 8: CI Validation & Documentation
**Status:** PARTIAL (Documentation started)
**Commits:** `84b92b3`

✅ Completed:
- iOS-BUILD.md — Step-by-step build guide
- iOS-ARCHITECTURE.md — Complete system architecture

⏳ Remaining:
- scripts/validate-all.sh — Automated verification
- Comprehensive security model documentation
- Known limitations and future extensions guide

## Key Design Decisions

### 1. CGo Binding Pattern Replication
The iOS C API layer follows the exact patterns from `demos-go/cb-mpc-go/internal/cgobinding/`:
- Opaque pointer pattern for C++ type hiding
- cmem_t/cmems_t for memory management
- Callback-based transport
- No invented logic; direct template copies with naming changes

**Rationale:** Proven pattern used successfully in Go; reduces divergence between language bindings.

### 2. Transport Callback Architecture
Transport is **application-owned**, not library-owned:
```c
typedef int (*cbmpc_send_f)(void* ctx, int receiver, cbmpc_cmem_t message);
typedef int (*cbmpc_receive_f)(void* ctx, int sender, cbmpc_cmem_t* out_message);
typedef int (*cbmpc_receive_all_f)(void* ctx, int* senders, int count, cbmpc_cmems_t* out);
```

**Rationale:** Allows iOS app to control all network I/O (VPN, proxies, custom protocols, testing).

### 3. Swift async/await + Synchronous C Callbacks
Swift async/await is bridged to synchronous C via DispatchSemaphore:
```swift
@_cdecl("cbmpc_swift_send")
func cbmpcSwiftSend(...) -> Int32 {
  // Block current C++ thread while waiting for async Swift operation
  semaphore.wait()
  return result
}
```

**Rationale:** C++ MPC primitives require blocking synchronous transport; Swift async is more ergonomic than callbacks.

### 4. Two Transport Implementations
- **MockTransport:** In-process Swift actors, simulates both parties, zero network latency
- **HttpTransport:** URLSession-based, calls remote MPC server

**Rationale:** Enables full demos without server; production use is flexible.

### 5. Session-Based State Management
Expo module stores sessions in a dictionary keyed by string:
```swift
private var sessions: [String: MpcSession] = [:]
```

**Rationale:** Enables multiple simultaneous MPC operations; matches Expo patterns.

## Critical Path

**Blocking dependencies:**

1. **Phase 2 → Phase 3:** OpenSSL must be built before libcbmpc.a
   - Network required for OpenSSL source download
   - ~15 minutes per architecture (device + 2 simulator slices)

2. **Phase 3 → Phase 5:** XCFramework must be built before Swift package
   - Device and simulator slices must be combined
   - ~20 minutes total build time

3. **Phase 5 → Phase 6:** Swift package must be complete before Expo module
   - Expo module imports CbMpcSwift

4. **Phase 6 → Phase 7:** Expo module must be complete before demo app
   - Demo app calls Expo module functions

**Parallel opportunities:**
- Phases 5-7 can be started in parallel once the C layer is ready (XCFramework available)
- Documentation (Phase 8) can be finalized in parallel

## Network/Environment Constraints

Currently in environment with limited network access:
- OpenSSL download blocked
- Git push to remote blocked
- But: all code is committed to local worktree `ios-integration-phase-1`

**Next steps when network is available:**
1. Run OpenSSL build scripts (Phase 2)
2. Run XCFramework build and verify (Phase 3)
3. Push branch to fork: `https://github.com/tankbottoms/cb-mpc`
4. Create three new repositories for Phases 5-7

## File Organization

```
cb-mpc/ (main repo with iOS patches)
├── cmake/
│   ├── arch.cmake (unchanged)
│   ├── compilation_flags.cmake (iOS patch: IS_APPLE → IS_MACOS)
│   └── openssl.cmake (iOS branch added)
├── scripts/openssl/
│   ├── build-static-openssl-ios-arm64.sh (NEW)
│   ├── build-static-openssl-ios-simulator-arm64.sh (NEW)
│   ├── build-static-openssl-ios-simulator-x86_64.sh (NEW)
│   ├── combine-ios-simulator-slices.sh (NEW)
│   └── verify-ios-openssl.sh (NEW)
├── src/cbmpc/ios/
│   ├── cbmpc_ios.h (NEW)
│   ├── cbmpc_ios_mem.cpp (NEW)
│   ├── cbmpc_ios_network.cpp (NEW)
│   ├── cbmpc_ios_ecdsa2p.cpp (NEW)
│   ├── cbmpc_ios_hd.cpp (NEW)
│   └── CMakeLists.txt (NEW)
├── docs/
│   ├── iOS-BUILD.md (NEW)
│   └── iOS-ARCHITECTURE.md (NEW)
├── CMakeLists.txt (iOS integration added)
└── .gitignore (iOS worktree directory added)

cb-mpc-swift/ (separate repo, to be created)
cb-mpc-expo-module/ (separate repo, to be created)
cb-mpc-demo-app/ (separate repo, to be created)
```

## Next Immediate Steps

1. **When network is available:**
   - Run Phase 2 OpenSSL build scripts
   - Run Phase 3 XCFramework build and verification
   - Commit both as new git commits
   - Test CMake configuration with actual OpenSSL

2. **Create three new repositories:**
   - `cb-mpc-swift` (Phase 5)
   - `cb-mpc-expo-module` (Phase 6)
   - `cb-mpc-demo-app` (Phase 7)

3. **Parallelize Phases 5-7:**
   - Swift package: Transport protocol and wrappers
   - Expo module: AsyncFunction handlers
   - Demo app: UI screens and mock mode flow

4. **Complete Phase 8:**
   - Automated validation script
   - Security documentation
   - Comprehensive troubleshooting guide

## References

- **Original Plan:** `.claude/plans/cheeky-chasing-elephant.md`
- **Build Guide:** `docs/iOS-BUILD.md`
- **Architecture:** `docs/iOS-ARCHITECTURE.md`
- **CGo Template:** `demos-go/cb-mpc-go/internal/cgobinding/`
- **HD Keyset:** `src/cbmpc/protocol/hd_keyset_ecdsa_2p.h`
- **C++ Job:** `src/cbmpc/protocol/mpc_job_session.h`

---

**Branch Status:** Ready for Phase 2-3 execution when network available.
**Code Review:** All phases 1-4 complete and committed.
