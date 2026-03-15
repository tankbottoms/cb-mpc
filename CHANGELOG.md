# Changelog

## [0.24.0] - 2026-03-14

### Added

- HD key derivation (BIP-32 child keys from master key shares)
- Transaction signing with EIP-155 replay protection
- Address book for saved recipient addresses
- Uniswap and CoW Protocol DEX service integration
- Safe multisig transaction support via SafeService
- EIP-712 typed data signing
- Peer-to-peer signing coordinator via MultipeerConnectivity
- Etherscan v2 API with multi-chain support
- Transactions tab view for browsing on-chain activity
- Contract interaction service for arbitrary ABI calls
- Platform compatibility layer (PlatformCompat) for iOS/macOS shared code
- macOS entitlements for cross-platform builds

### Changed

- Key server updated with new routes and types for HD derivation
- C API layer expanded with `cbmpc_ios_hd.cpp` for HD key operations
- Build scripts updated for xcframework generation

## [0.23.0] - 2026-03-13

### Added

- Server integration tests for key server round-trip verification
- Peer signing tests for device-to-device MPC validation
- Build/export scripts for iOS and macOS (ExportOptions plists)
- App icon set with full macOS icon sizes (16x16 through 512x512)

### Fixed

- CryptoKit SealedBox slice crash in Release builds (Data concatenation rebase issue)
- QR binary frame base64 encoding for reliable scanning

## [0.22.0] - 2026-03-12

### Added

- QR export/import with multi-part base64-encoded binary frames
- QR scanner view using AVCaptureMetadataOutput
- Visual guide documentation (DKG ceremony, signing operations, device-to-device, etc.)
- Expansion plan for visual guide coverage

### Technical Details

- maxQRBytes = 450 (binary frame limit), ~600 chars base64, QR version 9-10
- Data split evenly across parts (not fill-first-then-remainder)
- Camera-level deduplication prevents rapid-fire delegate crashes

## [0.21.0] - 2026-03-11

### Added

- App Store Connect metadata automation (`asc-metadata.sh`)
- Build changelog tracker (`build-changelog.sh`) with git-tag-based tracking
- Screenshot upload script for ASC (`asc-upload-screenshots.py`)
- App Store submission assets (15 screenshots, privacy policy, review info)
- Fastlane metadata directory structure (name, description, keywords, etc.)

### Changed

- Settings view reads version from Info.plist at runtime
- EtherscanService switched to v2 API with chainid parameter

## [0.20.0] - 2026-03-11

### Added

- Server DKG coordinator for Device+Server key generation
- Signing coordinator for unified 2-party signing (Device+Device and Device+Server)
- Create key sheet with server registration flow
- Sign message and sign transaction sheet views
- Server registration view with QR-based pairing
- Key dashboard with multi-key management
- Key detail view with signing and export actions
- Settings view with Face ID toggle and network selection

### Technical Details

- WebSocket transport for server MPC communication
- Job tracking for DKG and signing coordinator state
- Core Data schema updated for device pairing and server integration

## [0.19.0] - 2026-03-10

### Added

- CeremonySession and KeyShare data structures for ceremony state tracking
- KeyShareManager for Keychain-based key share storage with SecureEnclave protection
- CeremonyCoordinator state machine for DKG and signing ceremony lifecycle
- CeremonyMessage protocol for peer-to-peer ceremony communication
- DeviceDeviceDKGCoordinator wrapping PeerDKGCoordinator with ceremony lifecycle
- Ceremony-tracked DKG in ServerDKGCoordinator
- CeremonyView UI for real-time ceremony progress display
- E2E integration test scaffolds for DKG and signing flows
- Unit test target (CBMPCNativeTests) with comprehensive coverage
- Shared Xcode schemes for CI builds

### Technical Details

- Ceremony state machine: initialized -> committed -> signed -> complete
- Key shares protected in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- 30-second ceremony timeouts with automatic failure handling

## [0.18.0] - 2026-03-10

### Added

- CeremonySession and KeyShare data structures for ceremony state tracking
- KeyShareManager for Keychain-based key share storage with SecureEnclave protection
- CeremonyCoordinator state machine for DKG and signing ceremony lifecycle
- CeremonyMessage protocol for peer-to-peer ceremony communication over MultipeerConnectivity
- DeviceDeviceDKGCoordinator wrapping PeerDKGCoordinator with ceremony lifecycle
- Ceremony-tracked DKG in ServerDKGCoordinator for Device+Server key generation
- SigningCoordinator for unified 2-party signing (Device+Device and Device+Server)
- CeremonyView UI for real-time ceremony progress display
- E2E integration test scaffolds for DKG and signing flows

### Technical Details

- Ceremony state machine: initialized -> committed -> signed -> complete
- Key shares protected in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- CeremonyCoordinator uses @MainActor for thread-safe UI observation
- CeremonyMessage uses custom Codable with base64-encoded Data payloads
- 30-second ceremony timeouts with automatic failure handling

## [0.17.0] - 2026-03-10

### Added

- Transport origin UI integration (dynamic custody badges)
- Co-signer reference storage for server-backed and peer-backed keys
- DeviceInfo helper for hardware-specific model identification
- Automatic shared key generation after device pairing
- Paired device share count tracking after DKG completion
