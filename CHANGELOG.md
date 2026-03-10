# Changelog

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
