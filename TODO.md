# CB-MPC Feature Roadmap

## Completed

### Foundation (v0.1 - v0.6)

- [x] C++ MPC library compiled to xcframework (iOS arm64 + simulator)
- [x] C API bridging layer (`cbmpc_ios.h`) with 40+ exposed functions
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
- [x] Multi-part QR export/import with base64-encoded binary frames (max 450 bytes per frame)
- [x] Network tab with device discovery
- [x] Device pairing via MultipeerConnectivity (Bonjour `_cbmpc._tcp`)
- [x] 6-tab navigation layout
- [x] Etherscan v2 API integration (balance, transactions)

### Server Integration (v0.16 - v0.18)

- [x] Key server on Cloudflare Workers with Durable Objects
  - DeviceRegistry -- device registration and auth
  - DKGSession -- distributed key generation sessions
  - KeyVault -- server-side key share storage
  - SignSession -- signing session coordination
- [x] Server API client with JWT auth and WebSocket transport
- [x] Server registration view with QR-based pairing
- [x] Server DKG coordinator (device + server key generation)
- [x] Peer DKG coordinator (device-to-device key generation)
- [x] Signing coordinator for unified 2-party signing (device-device and device-server)
- [x] Transport origin UI (dynamic custody badges showing key share locations)
- [x] Co-signer reference storage
- [x] DeviceInfo helper for hardware model identification
- [x] Privacy policy endpoint on key server

### Ceremony and Testing (v0.18 - v0.22)

- [x] CeremonySession and KeyShare data structures for ceremony state tracking
- [x] CeremonyCoordinator state machine (initialized -> committed -> signed -> complete)
- [x] KeyShareManager for Keychain storage with SecureEnclave protection
- [x] CeremonyView UI for real-time ceremony progress display
- [x] DeviceDeviceDKGCoordinator wrapping peer DKG with ceremony lifecycle
- [x] Ceremony-tracked DKG in ServerDKGCoordinator
- [x] SigningCoordinator for 2-party signing ceremonies
- [x] E2E integration test scaffolds for DKG and signing flows
- [x] Unit test target (CBMPCNativeTests) with coverage
- [x] Shared Xcode schemes for CI builds

### App Store and Release (v0.22 - v0.24)

- [x] App Store Connect automation (`release.sh`, `build-changelog.sh`, `asc-metadata.sh`)
- [x] TestFlight build pipeline with approval gates
- [x] Changelog generation with git tag integration
- [x] 12+ interactive HTML visual guide pages
- [x] HD key operations in C API (`cbmpc_ios_hd.cpp`)
- [x] macOS target support
- [x] App icon generation with layered party cat themes

### Services (models created, integration pending)

- [x] EIP-712 typed data signer (`EIP712Signer.swift`)
- [x] Safe multisig service (`SafeService.swift`)
- [x] Uniswap service (`UniswapService.swift`)
- [x] Cow Protocol service (`CowService.swift`)
- [x] Contract ABI service (`ContractService.swift`)
- [x] Address book (`AddressBook.swift`)
- [x] Transactions tab view (`TransactionsTabView.swift`)

---

## Priorities (Future Work)

### P1: Core Wallet Features

**1. Simple Private Key Management**
- Import/export raw private keys (hex, WIF formats)
- Display private key with copy-to-clipboard and QR
- Basic single-key ECDSA signing (no MPC -- for testing and comparison)
- Clear UI distinction between MPC keys and simple keys
- Private key derivation from entropy
- Files: new `Views/SimpleKeyView.swift`, modify `KeyStore.swift`

**2. Seed Phrase (BIP-39)**
- Generate 12/24-word mnemonic from entropy
- Display word grid with numbered positions
- Verify backup: user re-enters words in order (shuffle verification)
- Derive private key from mnemonic + optional passphrase
- BIP-44 derivation path display (`m/44'/60'/0'/0/0` for ETH)
- Persist mnemonic in Keychain with biometric protection
- Files: new `Models/BIP39.swift`, new `Views/SeedPhraseView.swift`

**3. Shamir Secret Sharing**
- Split private key into N shares with K-of-N threshold
- Visual share management (cards showing share index, assigned holder name)
- Reconstruct key from K shares (gather via QR scan or manual entry)
- Export individual shares via QR code or file
- Access structure visualization (who holds what, what combinations unlock)
- Uses existing `CBMPCAccessStructure.swift` and `AccessStructureDemoView.swift` as base
- Files: new `Views/ShamirSplitView.swift`, new `Views/ShamirReconstructView.swift`

### P2: MPC Production

**4. MPC 2-Party Key (Production Quality)**
- Move from local 2-party simulation to real protocol over network transport
- Key share location indicators ("Your share: This Device", "Counterparty: Server" or "Peer")
- Key health dashboard: last refresh timestamp, backup status, counterparty online/offline
- Key refresh protocol (re-share without changing public key)
- Builds on: `ServerDKGCoordinator`, `SigningCoordinator`, `CeremonyCoordinator`
- Files: modify `KeyDetailView.swift`, new `Views/KeyHealthView.swift`

**5. MultipeerConnectivity Polish**
- Reliable peer discovery with retry and timeout handling
- Session recovery after disconnect (resume ceremony from last successful round)
- Multi-round MPC protocol over Bluetooth/WiFi Direct
- Visual connection quality indicators (signal strength, latency)
- Support for N>2 party configurations
- Builds on: `PeerConnectionManager.swift`, `MultipeerTransport.swift`

**6. Commitment Server Integration**
- Full round-trip DKG with Cloudflare Worker as Party 1
- Persistent session management (resume interrupted ceremonies)
- Server health monitoring from app (heartbeat, version, latency)
- Automatic reconnection with exponential backoff
- TLS certificate pinning
- Builds on: `ServerAPIClient.swift`, `WebSocketTransport.swift`

**7. Key Server Production Deployment**
- Deploy key server to production Cloudflare Workers
- Real DKG + signing with server holding Party 1 share
- Key refresh via server
- Server-side key share audit logging
- Admin dashboard for key server status
- Files: `key-server/` -- deploy via `wrangler deploy`

### P3: Transaction Features

**8. ETH Transfer from Device**
- Originate ETH transfer transactions (to address, amount, gas)
- Gas estimation (EIP-1559 base fee + priority fee from Etherscan API)
- Transaction signing via 2-party MPC (device signs with server/peer counterparty)
- Broadcast to Ethereum network via Etherscan or Infura
- Confirmation tracking with block explorer links
- Transaction history view (builds on existing `TransactionsTabView.swift`)
- Builds on: `EtherscanService.swift`, `SigningCoordinator.swift`

**9. Bitcoin Wallet**
- BIP-44 derivation for Bitcoin (`m/44'/0'/0'`)
- Bitcoin address generation (P2PKH, P2WPKH, P2TR/Taproot)
- UTXO tracking via Blockstream/Mempool API
- Transaction construction (input selection, change output, fee calculation)
- Transaction signing via MPC
- Fee estimation (sat/vbyte from mempool API)
- Files: new `Models/BitcoinService.swift`, new `Views/BitcoinWalletView.swift`

### P4: Key Safety

**10. USB-C Key Backup**
- Export encrypted key shares to external USB-C drive via UIDocumentPickerViewController
- AES-256-GCM encryption with device-bound key wrapping
- Backup contents: `encrypted_share.pve`, `public_key.pem`, `metadata.json`
- Verification screen with integrity checks (SHA-256 hash, ZK proof)
- Restore flow: detect drive, validate backup, import shares to Keychain
- Backup manifest with metadata (date, device model, key IDs, curve)
- Files: new `Models/USBBackupManager.swift`, new `Views/BackupFlowView.swift`, new `Views/RestoreFlowView.swift`

**11. Key Location Dashboard**
- Visual map showing where each share lives (this device / server / peer device / USB drive)
- Health indicators per share (last seen, last refresh, backup age)
- Alert for shares that haven't been refreshed in >30 days
- One-tap refresh for stale shares
- Export/migrate share between storage locations
- "Key Topology" view showing the full custody arrangement
- Files: new `Views/KeyTopologyView.swift`

### P5: DeFi Integration

**12. Uniswap / Cowswap**
- Token swap interface (select token pair, amount, slippage tolerance)
- EIP-712 typed data signing for swap orders
- Two modes: sign on device (direct swap) or via server relay (server constructs and submits)
- Price quotes from Uniswap v3 and Cow Protocol APIs
- Swap execution and confirmation tracking
- Integration with existing `UniswapService.swift` and `CowService.swift` models
- Files: modify `UniswapService.swift`, `CowService.swift`, new `Views/SwapView.swift`
