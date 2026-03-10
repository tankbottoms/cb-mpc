# CB-MPC Key Generation Analysis

A comprehensive analysis of the key generation schemes, signing protocols, and multi-party architecture in the CB-MPC (Coinbase Multi-Party Computation) library.

---

## Table of Contents

- [1. Executive Summary](#1-executive-summary)
- [2. Cryptographic Primitives](#2-cryptographic-primitives)
- [3. Key Generation Schemes](#3-key-generation-schemes)
  - [3.1 Single-Party Key Generation](#31-single-party-key-generation)
  - [3.2 Two-Party DKG (Current iOS Implementation)](#32-two-party-dkg)
  - [3.3 N-Party Threshold DKG (Go Demo)](#33-n-party-threshold-dkg)
- [4. Signing Protocols](#4-signing-protocols)
  - [4.1 Two-Party ECDSA Signing](#41-two-party-ecdsa-signing)
  - [4.2 Multi-Party ECDSA Signing](#42-multi-party-ecdsa-signing)
  - [4.3 Threshold ECDSA Signing](#43-threshold-ecdsa-signing)
  - [4.4 EdDSA Signing](#44-eddsa-signing)
  - [4.5 Schnorr / BIP-340 Signing](#45-schnorr--bip-340-signing)
- [5. HD Key Derivation](#5-hd-key-derivation)
- [6. Key Types in the iOS App](#6-key-types-in-the-ios-app)
- [7. Access Structures](#7-access-structures)
- [8. Multi-Device Architecture (Future)](#8-multi-device-architecture)
  - [8.1 Device Pairing](#81-device-pairing)
  - [8.2 Custody Models](#82-custody-models)
  - [8.3 Recovery Scenarios](#83-recovery-scenarios)
- [9. Transport Layer](#9-transport-layer)
- [10. UX Flow Diagrams](#10-ux-flow-diagrams)
- [11. Security Considerations](#11-security-considerations)
- [12. References](#12-references)

---

## 1. Executive Summary

CB-MPC is a threshold cryptography library that enables private keys to be split across multiple parties such that no single party ever holds the complete key. The library supports:

- **2-party ECDSA** with Paillier encryption (optimized for mobile/two-device scenarios)
- **N-party ECDSA** with oblivious transfer (for arbitrary party counts)
- **Threshold ECDSA** with access structures (t-of-n quorum policies)
- **2-party and N-party EdDSA** (Ed25519)
- **Schnorr signatures** (EdDSA and BIP-340 variants)
- **HD key derivation** (BIP-32/44 compatible, with MPC-safe derivation)
- **Key refresh** (re-randomize shares without changing the public key)

The iOS app currently implements **2-party ECDSA** with both key shares stored locally on the same device. This document describes the full protocol stack and outlines the path to multi-device, threshold-based key management.

### Architecture Stack

```
+----------------------------------------------------------+
|  iOS App (SwiftUI)                                       |
|  KeyDashboardView, SignMessageSheetView, etc.            |
+----------------------------------------------------------+
|  Swift Models                                            |
|  KeyStore, CBMPCCryptoEngine, ManagedKey                 |
+----------------------------------------------------------+
|  C Bridging Layer (cbmpc_ios.h)                          |
|  cbmpc_ecdsa2p_dkg, cbmpc_ecdsa2p_sign, etc.            |
+----------------------------------------------------------+
|  C++ Protocol Layer                                      |
|  ecdsa_2p, ecdsa_mp, ec_dkg, schnorr, eddsa, hd_keyset  |
+----------------------------------------------------------+
|  Crypto Primitives                                       |
|  Paillier, ElGamal, Pedersen, OT, Secret Sharing         |
+----------------------------------------------------------+
|  OpenSSL + secp256k1                                     |
+----------------------------------------------------------+
```

---

## 2. Cryptographic Primitives

### Elliptic Curves

| Curve | OpenSSL NID | Use |
|-------|-------------|-----|
| secp256k1 | 714 | Bitcoin/Ethereum ECDSA |
| prime256v1 (P-256) | 415 | General ECDSA |
| Ed25519 | -- | EdDSA signatures |

### Paillier Encryption

Used exclusively in **2-party ECDSA**. One party encrypts its key share under a Paillier key, enabling the other party to compute on the ciphertext during signing without learning the plaintext share.

The Paillier key generation is interactive (4-step protocol) with zero-knowledge proofs:

```
P1 generates Paillier keypair (N, lambda)
P1 encrypts x1: c_key = Enc(x1)
P1 proves:
  - N is a valid Paillier modulus (no small factors)
  - c_key encrypts the same value committed in Q1
  - x1 is in range [0, q)
P2 verifies all proofs before accepting c_key
```

**Source:** `src/cbmpc/protocol/ecdsa_2p.h` -- `paillier_gen_interactive_t`

### Oblivious Transfer (OT)

Used in **N-party ECDSA signing** (not needed for 2-party). The PVW BaseOT protocol enables pairwise secret exchange:

```cpp
// src/cbmpc/protocol/ot.h
struct base_ot_protocol_pvw_ctx_t {
    enum { l = 128 };  // 128-bit OT
    error_t step1_R2S(const bits_t& b);       // Receiver -> Sender
    error_t step2_S2R(const vector<buf_t>& x0, const vector<buf_t>& x1);  // Sender -> Receiver
    error_t output_R(vector<buf_t>& x);       // Receiver gets selected values
};
```

### Secret Sharing

Access structures are defined as trees with four node types:

| Node Type | Semantics | Example |
|-----------|-----------|---------|
| LEAF | Terminal party | "device-A" |
| AND | All children required | Both shares needed |
| OR | Any one child sufficient | Either device works |
| THRESHOLD | K-of-N children | 2-of-3 quorum |

```cpp
// src/cbmpc/crypto/secret_sharing.h
enum class node_e { NONE=0, LEAF=1, AND=2, OR=3, THRESHOLD=4 };

// Sharing functions
vector<bn_t> share_and(const mod_t& q, const bn_t& x, int n, ...);
pair<vector<bn_t>, vector<bn_t>> share_threshold(const mod_t& q, const bn_t& a,
                                                  int threshold, int n, ...);
```

### Commitment Schemes

All DKG protocols use commit-reveal to prevent rushing attacks:

1. P1 commits to its share: `com = Commit(Q1, decom)`
2. P2 sends Q2 in the clear
3. P1 reveals decommitment
4. P2 verifies commitment matches

### Zero-Knowledge Proofs

| Proof | File | Purpose |
|-------|------|---------|
| UC Discrete Log | `zk_ec.h` -- `uc_dl_t` | Prove knowledge of DL (DKG) |
| UC Batch DL | `zk_ec.h` -- `uc_batch_dl_t` | Batch DL proofs |
| Diffie-Hellman | `zk_ec.h` -- `dh_t` | Prove DH tuple |
| Valid Paillier | `zk_paillier.h` -- `valid_paillier_t` | Modulus has no small factors |
| Paillier Zero | `zk_paillier.h` -- `paillier_zero_t` | Ciphertext encrypts 0 |
| Two Paillier Equal | `zk_paillier.h` -- `two_paillier_equal_t` | Two ciphertexts encrypt same value |
| Range Pedersen | `zk_pedersen.h` -- `range_pedersen_t` | Value is in range |
| UC ElGamal Commit | `zk_elgamal_com.h` -- `uc_elgamal_com_t` | ElGamal commitment proof |
| ElGamal Mult | `zk_elgamal_com.h` -- `elgamal_com_mult_t` | Product of encrypted values |
| Unknown Order DL | `zk_unknown_order.h` -- `unknown_order_dl_t` | DL in unknown-order group |

All use Fischlin transform for UC-security (non-interactive in random oracle model).

**Security parameters:**
- SEC_P_COM = 128 (computational security)
- SEC_P_STAT = 64 (statistical security)

---

## 3. Key Generation Schemes

### 3.1 Single-Party Key Generation

The iOS app supports importing keys from external sources:

**From Seed Phrase (BIP-39 -> BIP-32)**

1. User provides 12/24-word mnemonic
2. App derives HD master key via BIP-32
3. Master key is split into 2 MPC shares via local 2-party DKG
4. Both shares stored on device

**From Raw Private Key**

1. User provides hex-encoded private key
2. Key is split into 2 MPC shares via local 2-party DKG
3. Both shares stored on device

**From Storage File (KeyStore V3)**

1. User imports JSON keystore file
2. Key data stored directly (may or may not be MPC shares)

In all cases, the app calls `CBMPCCryptoEngine.generateKey(curveCode:)` which runs a 2-party DKG locally using `LocalTwoPartyRunner`.

### 3.2 Two-Party DKG

**Current iOS implementation.** Both parties run on the same device using an in-memory transport.

#### Protocol: EC-DKG-2P (4 rounds)

```
Source: src/cbmpc/protocol/ec_dkg.h -- dkg_2p_t

Round 1: P1 -> P2
  P1 generates random x1
  P1 computes Q1 = x1 * G
  P1 commits: com = Commit(Q1)
  P1 sends com

Round 2: P2 -> P1
  P2 generates random x2
  P2 computes Q2 = x2 * G
  P2 proves knowledge: pi_2 = UC-DL(Q2, x2)
  P2 sends (Q2, pi_2)

Round 3: P1 -> P2
  P1 decommits Q1
  P1 proves knowledge: pi_1 = UC-DL(Q1, x1)
  P1 sends (Q1, pi_1, decom)

Round 4: P2 verifies
  P2 verifies commitment and proof
  Both compute Q = Q1 + Q2 (public key)
  Each party stores their share (x1 or x2)
```

#### Key Share Structure

```cpp
// src/cbmpc/protocol/ec_dkg.h
struct key_share_2p_t {
    party_t role;       // p1 or p2
    ecurve_t curve;     // secp256k1 (714)
    ecc_point_t Q;      // Shared public key
    bn_t x_share;       // This party's private key share
};
```

#### ECDSA 2-Party Key (with Paillier)

The ECDSA-optimized variant adds Paillier encryption for efficient signing:

```cpp
// src/cbmpc/protocol/ecdsa_2p.h
struct key_t {
    party_t role;
    ecurve_t curve;
    ecc_point_t Q;           // Public key
    bn_t x_share;            // Private key share
    bn_t c_key;              // Paillier ciphertext of x
    crypto::paillier_t paillier;  // Paillier key
};
```

#### iOS C API

```c
// cbmpc_ios.h
int cbmpc_ecdsa2p_dkg(cbmpc_job2p_t* job, int curve_code, cbmpc_ecdsa2p_key_t* out);
int cbmpc_ecdsa2p_refresh(cbmpc_job2p_t* job, cbmpc_ecdsa2p_key_t* key, cbmpc_ecdsa2p_key_t* out);
```

#### Swift Wrapper

```swift
// CBMPCCryptoEngine.swift
func generateKey(curveCode: Int) throws -> (publicKey: Data, serializedKey: Data) {
    let (k0, k1) = try LocalTwoPartyRunner.run(partyNames: ["local", "remote"]) { job, role in
        var keyVar = cbmpc_ecdsa2p_key_t()
        let result = cbmpc_ecdsa2p_dkg(job.cJob, Int32(curveCode), &keyVar)
        guard result == 0 else { throw CBMPCError.keyGenerationFailed }
        return CBMPCKeyShare(keyPtr: keyVar, curveCode: curveCode)
    }
    // Pack: [4-byte k0 length][k0 bytes][k1 bytes]
    ...
}
```

#### Key Share Serialization Format

```
Offset  Size     Field
0       4        k0_size (UInt32, little-endian)
4       k0_size  Party 0 key share (serialized)
4+k0    rest     Party 1 key share (serialized)
```

Both shares are stored in UserDefaults keyed by `key_{UUID}`.

#### Current Limitation

Both key shares live on the same device. The private key `x = x1 + x2 mod q` could theoretically be reconstructed from device storage. This is a development convenience -- the architecture supports true 2-party separation.

### 3.3 N-Party Threshold DKG

**Implemented in C++ and demonstrated in the Go threshold-ecdsa-web demo.**

#### Protocol: EC-DKG-Threshold-MP

```cpp
// src/cbmpc/protocol/ec_dkg.h
static error_t threshold_dkg(
    job_mp_t& job,
    const ecurve_t& curve,
    buf_t& sid,
    const crypto::ss::ac_t ac,         // Access structure (t-of-n)
    const party_set_t& quorum_party_set,
    key_share_mp_t& key
);
```

#### Go Demo Flow

```go
// demos-go/cmd/threshold-ecdsa-web/handlers.go

func runThresholdDKG(
    partyIndex int,
    quorumCount int,
    allPNameList []string,
    ac *mpc.AccessStructure,
    curve curve.Curve,
    messenger transport.Messenger,
) (*mpc.ECDSAMPCKey, error)
```

1. Party 0 initiates DKG with threshold parameter
2. All N parties participate (quorum is full set during DKG)
3. Access structure defines the t-of-n policy
4. Each party receives a multiplicative share of the key
5. Key shares saved to `keyshare_party_{name}.json`

#### Access Structure Construction

```go
// demos-go/cmd/threshold-ecdsa-web/handlers.go

func createThresholdAccessStructure(pnameList []string, threshold int, curve curve.Curve) mpc.AccessStructure {
    root := Threshold("", threshold)   // K-of-N root node
    for _, pname := range pnameList {
        root.Children = append(root.Children, Leaf(pname))
    }
    return AccessStructure{Root: root, Curve: curve}
}
```

#### Key Share Structure (N-Party)

```cpp
// src/cbmpc/protocol/ec_dkg.h
struct key_share_mp_t {
    bn_t x_share;
    ecc_point_t Q;
    crypto::ss::party_map_t<crypto::ecc_point_t> Qis;  // Public shares from all parties
    ecurve_t curve;
    crypto::pname_t party_name;
};
```

---

## 4. Signing Protocols

### 4.1 Two-Party ECDSA Signing

Uses Paillier homomorphic encryption for efficient 2-party computation.

```cpp
// src/cbmpc/protocol/ecdsa_2p.h
error_t sign(job_2p_t& job, buf_t& sid, const key_t& key, const mem_t msg, buf_t& sig);
error_t sign_batch(job_2p_t& job, buf_t& sid, const key_t& key,
                   const vector<mem_t>& msgs, vector<buf_t>& sigs);
```

#### Protocol Flow

```
Input: Both parties hold key shares (x1, x2), Paillier ciphertext c_key = Enc(x1)
       Message hash m to sign

1. Nonce Generation (similar to DKG)
   P1 generates k1, computes R1 = k1 * G
   P2 generates k2, computes R2 = k2 * G
   Commit-reveal to establish R = k1*k2 * G (without either learning k)

2. Partial Signature (Paillier homomorphic computation)
   P2 computes on encrypted share:
     c = Enc(k2^-1 * (m + r*x1)) using Paillier homomorphism on c_key
     Adds randomness: c' = c + Enc(k2^-1 * r * x2) + Enc(rho * q)
   P2 sends c' to P1 with ZK proof

3. Signature Assembly
   P1 decrypts c' to get s' = k1^-1 * (m + r*x)
   P1 normalizes s (low-S form for Bitcoin/Ethereum)
   P1 outputs DER-encoded (r, s)

ZK Proof: zk_ecdsa_sign_2pc_integer_commit_t
  Proves correct computation without revealing k2 or x2
```

#### iOS C API

```c
int cbmpc_ecdsa2p_sign(cbmpc_job2p_t* job, cbmpc_cmem_t sid,
                       cbmpc_ecdsa2p_key_t* key, cbmpc_cmems_t msgs,
                       cbmpc_cmems_t* out_sigs);
```

#### Swift Wrapper

```swift
// CBMPCCryptoEngine.swift
func signMessage(_ message: Data, keyData: Data, curveCode: Int) throws -> Data {
    let (keyShare0, keyShare1) = try Self.unpackKeyShares(keyData, curveCode: curveCode)
    let sessionId = UUID().uuidString.data(using: .utf8) ?? Data()
    let (sig0, _) = try LocalTwoPartyRunner.run(partyNames: ["local", "remote"]) { job, role in
        let keyShare = (role == 0) ? keyShare0 : keyShare1
        let sigs = try CBMPCSigner.signMessages([message], with: keyShare, sessionId: sessionId, job: job)
        return sigs.first ?? Data()
    }
    return sig0
}
```

#### Global Abort Variant

```cpp
error_t sign_with_global_abort(job_2p_t& job, buf_t& sid, const key_t& key,
                               const mem_t msg, buf_t& sig);
```

Provides identifiable abort -- if one party cheats, the other can prove who misbehaved.

### 4.2 Multi-Party ECDSA Signing

Uses OT (oblivious transfer) instead of Paillier for N-party generalization.

```cpp
// src/cbmpc/protocol/ecdsa_mp.h
error_t sign(job_mp_t& job, key_t& key, mem_t msg, const party_idx_t sig_receiver,
             const vector<vector<int>>& ot_role_map, buf_t& sig);
```

- `sig_receiver`: Only this party gets the final signature
- `ot_role_map`: Defines who plays sender/receiver in each OT pair
- All parties must participate (no threshold subset)

### 4.3 Threshold ECDSA Signing

Combines threshold DKG shares with N-party signing:

```go
// demos-go/cmd/threshold-ecdsa-web/handlers.go

func runThresholdSign(
    keyShareRef *mpc.ECDSAMPCKey,
    ac *mpc.AccessStructure,
    partyIndex int,
    quorumCount int,
    quorumPNames []string,
    inputMessage []byte,
    messenger transport.Messenger,
) ([]byte, []byte, error) {
    // 1. Convert multiplicative share to additive share
    additiveShare := keyShare.ToAdditiveShare(ac, quorumPNames)

    // 2. Hash the message
    hash := sha256(inputMessage)

    // 3. Sign with quorum subset
    sig := mpc.ECDSAMPCSign(job, &ECDSAMPCSignRequest{
        KeyShare:          additiveShare,
        Message:           hash,
        SignatureReceiver: 0,  // Party 0 gets signature
    })
}
```

Key insight: Threshold DKG produces **multiplicative shares** (Shamir-style). Before signing, each quorum member converts to an **additive share** using Lagrange interpolation coefficients. Then standard N-party ECDSA signing runs on the additive shares.

### 4.4 EdDSA Signing

Both 2-party and N-party variants exist:

```cpp
// src/cbmpc/protocol/eddsa.h

// 2-Party
namespace eddsa2pc {
    typedef schnorr2p::key_t key_t;
    error_t sign(job_2p_t& job, key_t& key, const mem_t& msg, buf_t& sig);
    error_t sign_batch(job_2p_t& job, key_t& key, const vector<mem_t>& msgs, vector<buf_t>& sigs);
}

// N-Party
namespace eddsampc {
    typedef schnorrmp::key_t key_t;
    error_t sign(job_mp_t& job, key_t& key, const mem_t& msg, party_idx_t sig_receiver, buf_t& sig);
}
```

Go API mirrors ECDSA:

```go
// demos-go/cb-mpc-go/api/mpc/eddsa_mp.go
func EDDSAMPCKeyGen(jobmp *JobMP, req *EDDSAMPCKeyGenRequest) (*EDDSAMPCKeyGenResponse, error)
func EDDSAMPCSign(jobmp *JobMP, req *EDDSAMPCSignRequest) (*EDDSAMPCSignResponse, error)
func EDDSAMPCThresholdDKG(jobmp *JobMP, req *EDDSAMPCThresholdDKGRequest) (*EDDSAMPCThresholdDKGResponse, error)
```

### 4.5 Schnorr / BIP-340 Signing

Supports both EdDSA and BIP-340 (Bitcoin Taproot) variants:

```cpp
// src/cbmpc/protocol/schnorr_2p.h
namespace schnorr2p {
    enum class variant_e { EdDSA, BIP340 };
    error_t sign(job_2p_t& job, key_t& key, const mem_t& msg, buf_t& sig, variant_e variant);
}

// src/cbmpc/protocol/schnorr_mp.h
namespace schnorrmp {
    error_t sign(job_mp_t& job, key_t& key, const mem_t& msg, party_idx_t sig_receiver,
                 buf_t& sig, variant_e variant);
}
```

---

## 5. HD Key Derivation

BIP-32 compatible hierarchical deterministic key derivation with MPC-safe protocols.

### HD Root Structure

```cpp
// src/cbmpc/protocol/hd_tree_bip32.h
struct hd_root_t {
    bn_t x_share;    // Private key share
    bn_t k_share;    // Chain code share
    ecc_point_t Q;   // Master public key
    ecc_point_t K;   // Master chain code public point
};
```

### 2-Party HD ECDSA Keyset

```cpp
// src/cbmpc/protocol/hd_keyset_ecdsa_2p.h
struct key_share_ecdsa_hdmpc_2p_t {
    hd_root_t root;
    paillier_t paillier;
    bn_t c_key;
    ecurve_t curve;
    party_idx_t party_index;

    static error_t dkg(job_2p_t& job, ecurve_t curve, key_share_ecdsa_hdmpc_2p_t& key);

    static error_t derive_keys(
        job_2p_t& job,
        const key_share_ecdsa_hdmpc_2p_t& key,
        const bip32_path_t& hardened_path,          // e.g., m/44'/60'/0'
        const vector<bip32_path_t>& non_hardened_paths,  // e.g., 0/0, 0/1, 0/2
        buf_t& sid,
        vector<ecdsa2pc::key_t>& derived_keys
    );

    static error_t refresh(job_2p_t& job, key_share_ecdsa_hdmpc_2p_t& current,
                           key_share_ecdsa_hdmpc_2p_t& new_keyset);
};
```

### 2-Party HD EdDSA Keyset

```cpp
// src/cbmpc/protocol/hd_keyset_eddsa_2p.h
struct key_share_eddsa_hdmpc_2p_t {
    hd_root_t root;
    ecurve_t curve;
    party_idx_t party_index;

    static error_t dkg(job_2p_t& job, ecurve_t curve, key_share_eddsa_hdmpc_2p_t& key);
    static error_t derive_keys(...);  // Same pattern as ECDSA
    static error_t refresh(...);
};
```

### iOS C API for HD

```c
int cbmpc_hd_ecdsa2p_dkg(cbmpc_job2p_t* job, int curve_code, cbmpc_hd_key_t* out);
int cbmpc_hd_ecdsa2p_derive(cbmpc_job2p_t* job, cbmpc_hd_key_t* key,
                            const int* path, int path_len,
                            cbmpc_ecdsa2p_key_t* out_child);
int cbmpc_hd_ecdsa2p_refresh(cbmpc_job2p_t* job, cbmpc_hd_key_t* key, cbmpc_hd_key_t* out);
```

### BIP-32 Path Handling

```cpp
class bip32_path_t {
    void append(uint32_t index);
    int count() const;
    uint32_t operator[](int i) const;
    bool empty() const;
};

// Non-hardened derivation (public derivation, no interaction needed)
vector<bn_t> non_hard_derive(const ecc_point_t& Q, mem_t chain_code,
                             const vector<bip32_path_t>& paths);
```

Key property: **Non-hardened derivation** can be done without MPC interaction (just EC point addition). **Hardened derivation** requires the private key, so both parties must participate interactively.

### Derivation Presets in iOS App

| Standard | Path Pattern | Example |
|----------|-------------|---------|
| MetaMask | `m/44'/60'/0'/0/X` | `m/44'/60'/0'/0/0` |
| Ledger Live | `m/44'/60'/X'/0/0` | `m/44'/60'/0'/0/0` |
| MetaMask (seed) | `m/44'/60'/0'/0` | Truncated |
| Custom | Any BIP-44 | User-defined |

---

## 6. Key Types in the iOS App

```swift
// ManagedKeyModel.swift
enum KeyType: String, CaseIterable {
    case simple = "simple"      // ECDSA (secp256k1 or P-256)
    case hdMaster = "hdMaster"  // HD Master key (BIP-32 root)
    case hdChild = "hdChild"    // HD Child key (derived from master)
}

struct ManagedKey: Identifiable {
    let id: UUID
    let name: String
    let publicKey: String        // Hex-encoded compressed public key (33 bytes)
    let keyType: KeyType
    let curveCode: Int32         // 714 = secp256k1, 415 = P-256
    let derivationPath: String?  // BIP-32 path for HD keys
    let parentKeyId: UUID?       // Parent key for HD children
    let storageLocation: StorageLocation  // secureEnclave or keychain
    let createdAt: Date
    var signingRecords: [SigningRecord]
}
```

### Key Type to Protocol Mapping

| Key Type | DKG Protocol | Signing Protocol | HD Derivation |
|----------|-------------|-----------------|---------------|
| Simple ECDSA | `cbmpc_ecdsa2p_dkg` | `cbmpc_ecdsa2p_sign` | N/A |
| HD Master ECDSA | `cbmpc_hd_ecdsa2p_dkg` | (derive first) | `cbmpc_hd_ecdsa2p_derive` |
| HD Child ECDSA | (derived from master) | `cbmpc_ecdsa2p_sign` | N/A |
| Simple EdDSA | EC-DKG-2P (Ed25519) | `eddsa2pc::sign` | N/A |
| HD Master EdDSA | `hd_keyset_eddsa_2p::dkg` | (derive first) | `derive_keys` |

### Signature Verification

Verification is stateless -- no key shares needed, only the public key:

```swift
// CBMPCCryptoEngine.swift
static func verifySignature(curveCode: Int, publicKey: Data,
                            messageHash: Data, derSignature: Data) -> Bool {
    // Calls cbmpc_ecdsa_verify via C bridge
}
```

---

## 7. Access Structures

Access structures define **who must participate** for key operations (signing, refresh).

### Node Types

```
THRESHOLD(K=2)
  |-- LEAF("device-A")
  |-- LEAF("device-B")
  |-- LEAF("server")
```

This tree means: any 2 of 3 parties can sign.

### Complex Policies

Access structures support arbitrary combinations:

```
AND
  |-- THRESHOLD(K=2)       # At least 2 devices
  |     |-- LEAF("phone")
  |     |-- LEAF("tablet")
  |     |-- LEAF("laptop")
  |
  |-- OR                    # Plus server approval
        |-- LEAF("server-primary")
        |-- LEAF("server-backup")
```

### C API

```c
cbmpc_ac_node_t* cbmpc_ac_node_new(int node_type, const char* name, int threshold);
void cbmpc_ac_node_add_child(cbmpc_ac_node_t* parent, cbmpc_ac_node_t* child);
cbmpc_ac_t* cbmpc_ac_new(cbmpc_ac_node_t* root, cbmpc_curve_t* curve);
```

### Go API

```go
// demos-go/cb-mpc-go/api/mpc/access_structure.go
func Leaf(name string) *AccessNode
func And(name string, kids ...*AccessNode) *AccessNode
func Or(name string, kids ...*AccessNode) *AccessNode
func Threshold(name string, k int, kids ...*AccessNode) *AccessNode
```

---

## 8. Multi-Device Architecture

### 8.1 Device Pairing

**Not yet implemented in iOS.** Planned approaches:

#### QR Code Pairing

```
Device A (Initiator)              Device B (Joiner)
  |                                  |
  |-- Generate pairing session ID -->|  (via QR code)
  |-- Exchange mTLS certificates --->|  (via QR code sequence)
  |<- Confirm pairing key ----------|  (via QR code)
  |                                  |
  |-- Run 2-party DKG ------------->|  (via network, mTLS)
  |-- Each stores 1 key share       |
```

Each device gets exactly one key share. Neither device can sign alone.

#### Bluetooth Pairing

Same protocol flow, but using Bluetooth Low Energy (BLE) for transport instead of network + QR bootstrapping. BLE provides:
- Proximity verification (devices must be physically close)
- Encrypted channel after pairing
- No internet required

### 8.2 Custody Models

#### Model 1: Single Device (Current)

```
+-------------------+
|  Device           |
|  [Share 0]        |
|  [Share 1]        |
|  Can sign alone   |
+-------------------+
```

Both shares on one device. Convenient for development and testing. Not suitable for production security -- device compromise reveals both shares.

**Settings:** 1-party default

#### Model 2: Two Devices

```
+-------------------+     +-------------------+
|  Device A         |     |  Device B         |
|  [Share 0]        |     |  [Share 1]        |
|  Cannot sign      |     |  Cannot sign      |
|  alone            |     |  alone            |
+-------------------+     +-------------------+
        |                         |
        +--- Both needed to sign -+
```

True 2-party security. Key share never crosses device boundary. Signing requires both devices online simultaneously.

**Settings:** 2-party default

#### Model 3: Two Devices + Server

```
+----------+     +----------+     +----------+
| Device A |     | Device B |     | Server   |
| [Share 0]|     | [Share 1]|     | [Share 2]|
+----------+     +----------+     +----------+
      |               |               |
      +-- 2-of-3 threshold signing ---+
```

Any 2 of 3 parties can sign. Server provides:
- Backup if one device is lost
- Policy enforcement (rate limits, whitelists)
- Audit logging

**Access structure:** `Threshold("", 2, Leaf("device-a"), Leaf("device-b"), Leaf("server"))`

#### Model 4: N-Party Organization

```
+--------+  +--------+  +--------+  +--------+  +--------+
| Admin1 |  | Admin2 |  | Admin3 |  | Admin4 |  | Admin5 |
| [Sh 0] |  | [Sh 1] |  | [Sh 2] |  | [Sh 3] |  | [Sh 4] |
+--------+  +--------+  +--------+  +--------+  +--------+
                |              |              |
                +-- 3-of-5 threshold signing -+
```

Enterprise custody: 3 of 5 administrators required to authorize transactions.

### 8.3 Recovery Scenarios

#### Device Loss With Backup

If Device A is lost and the key was exported (encrypted QR or file):

1. Get a new device
2. Import key share from backup
3. Run **key refresh** to invalidate old device's share:
   ```
   cbmpc_ecdsa2p_refresh(job, old_key, new_key)
   ```
4. Public key stays the same, but shares are re-randomized

#### Device Loss Without Backup (Threshold)

If one device in a t-of-n scheme is lost:

1. Remaining t parties form a quorum
2. Run **threshold refresh** to generate new shares for a replacement device:
   ```cpp
   key_share_mp_t::threshold_refresh(job, curve, sid, ac, quorum, key, new_key)
   ```
3. Old device's share becomes useless
4. Public key remains unchanged

#### Key Refresh (Proactive Security)

Even without device loss, periodic refresh prevents accumulation attacks:

```
Before refresh: x = x1 + x2
  x1' = x1 + delta
  x2' = x2 - delta
After refresh:  x = x1' + x2' (same key, new shares)
```

```cpp
// 2-party refresh
static error_t refresh(job_2p_t& job, const key_share_2p_t& key, key_share_2p_t& new_key);

// N-party refresh
static error_t refresh(job_mp_t& job, buf_t& sid, const key_share_mp_t& current, key_share_mp_t& new_key);

// Threshold refresh
static error_t threshold_refresh(job_mp_t& job, const ecurve_t& curve, buf_t& sid,
                                 const crypto::ss::ac_t ac, const party_set_t& quorum,
                                 key_share_mp_t& key, key_share_mp_t& new_key);
```

#### Social Recovery

Using a 2-of-3 access structure with trusted contacts:

```
Threshold(2)
  |-- Leaf("owner-phone")
  |-- Leaf("trusted-friend-1")
  |-- Leaf("trusted-friend-2")
```

If the owner loses their phone, two friends can reconstruct signing ability and transfer funds to a new key.

---

## 9. Transport Layer

### In-Memory (Current iOS)

`LocalTwoPartyRunner` runs both parties in the same process using synchronous message passing. No network involved.

### mTLS (Go Demo)

The Go demo uses mutual TLS with certificate-based party identity:

```go
// demos-go/cb-mpc-go/api/transport/messenger.go
type Messenger interface {
    MessageSend(ctx context.Context, receiver int, buffer []byte) error
    MessageReceive(ctx context.Context, sender int) ([]byte, error)
    MessagesReceive(ctx context.Context, senders []int) ([][]byte, error)
}
```

Key properties:
- **Deterministic connection pattern:** Lower-index parties connect to higher-index parties
- **Party names derived from certificates:** `SHA256(PKIX-encoded public key)` -> hex string
- **Message framing:** 4-byte big-endian length prefix + payload
- **Max message:** 10 MB
- **TLS 1.3 with mutual authentication**

### C API Transport Callbacks

```c
typedef int (*cbmpc_send_f)(void* ctx, int receiver, cbmpc_cmem_t message);
typedef int (*cbmpc_receive_f)(void* ctx, int sender, cbmpc_cmem_t* out_message);

typedef struct {
    cbmpc_send_f        send_fn;
    cbmpc_receive_f     receive_fn;
    cbmpc_receive_all_f receive_all_fn;
} cbmpc_transport_t;
```

Any transport (BLE, WebSocket, QR relay) can be plugged in by implementing these three callbacks.

---

## 10. UX Flow Diagrams

### Key Generation (2-Party Local)

```
User                    iOS App                 C++ Library
  |                       |                        |
  |-- "Generate Key" ---->|                        |
  |                       |-- Create Job2P ------->|
  |                       |   (in-memory transport)|
  |                       |                        |
  |                       |-- cbmpc_ecdsa2p_dkg -->|
  |                       |   Party 0: Round 1     |
  |                       |   Party 1: Round 2     |
  |                       |   Party 0: Round 3     |
  |                       |   Party 1: Round 4     |
  |                       |<-- (key0, key1) -------|
  |                       |                        |
  |                       |-- Pack shares:         |
  |                       |   [4B len][k0][k1]     |
  |                       |-- Store in UserDefaults|
  |                       |-- Save to CoreData     |
  |<-- "Key Created" -----|                        |
```

### Message Signing (2-Party Local)

```
User                    iOS App                 C++ Library
  |                       |                        |
  |-- "Sign Message" ---->|                        |
  |   (message text)      |-- Unpack shares ------>|
  |                       |   from UserDefaults    |
  |                       |                        |
  |                       |-- SHA-256(message) --->|
  |                       |                        |
  |                       |-- cbmpc_ecdsa2p_sign ->|
  |                       |   Party 0: nonce gen   |
  |                       |   Party 1: nonce gen   |
  |                       |   (Paillier hom. comp) |
  |                       |   Party 0: assemble    |
  |                       |<-- DER signature ------|
  |                       |                        |
  |                       |-- Record to CoreData   |
  |<-- Signature (hex) ---|                        |
```

### Threshold Signing (N-Party, Future)

```
Device A          Device B          Server           C++ Library
   |                 |                |                  |
   |-- "Sign tx" --->|                |                  |
   |                 |                |                  |
   |-- Connect to quorum via mTLS ---|                  |
   |                 |                |                  |
   |-- ToAdditive ---|----------------|---------------->|
   |   (Lagrange     |                |                  |
   |    coefficients)|                |                  |
   |                 |                |                  |
   |-- ECDSAMPCSign -|----------------|---------------->|
   |   Round 1: nonces                |                  |
   |   Round 2: partial sigs          |                  |
   |   Round 3: assembly (to party 0) |                  |
   |                 |                |                  |
   |<-- DER signature ----------------------------------|
```

### Multi-Device Pairing (Future)

```
Device A (Initiator)                Device B (Joiner)
   |                                    |
   |-- Show QR: session_id ------------>| (camera scan)
   |                                    |
   |<- Show QR: cert_B + ack ----------| (camera scan)
   |                                    |
   |-- Establish mTLS connection ------>|
   |   (using exchanged certificates)   |
   |                                    |
   |== Run 2-Party DKG ===============>|
   |   Round 1-4 over mTLS             |
   |                                    |
   |-- Store share 0                    |-- Store share 1
   |-- Save public key                 |-- Save public key
   |                                    |
   |   [Cannot sign alone]             |   [Cannot sign alone]
```

---

## 11. Security Considerations

### Key Share Isolation

- Each party's share is a random value that reveals nothing about the full private key
- Shares are never transmitted in the clear -- only ZK proofs and encrypted values cross party boundaries
- The full private key `x = x1 + x2 mod q` is never reconstructed at any point during signing

### Transport Security

- Go demo: mTLS (mutual TLS 1.3) with certificate-pinned party identity
- iOS (current): In-memory transport (no network exposure)
- iOS (future): BLE with ECDH key agreement, or mTLS over local network
- QR export: AES-256-GCM encryption with user-provided passphrase, CRC32 integrity checks, zlib compression

### Side-Channel Protections

The C++ library includes:
- Constant-time comparison for secrets (`buf_t` comparison)
- Randomized blinding in Paillier operations
- UC-secure ZK proofs (simulator-extractable in the random oracle model)
- Session IDs prevent replay attacks across sessions

### Known CryptoKit Bug (iOS)

**CryptoKit SealedBox Slice Crash:** When using `AES.GCM.SealedBox`, the `ciphertext` and `tag` properties return internal slices with non-zero `startIndex`. The `+` operator may not properly rebase indices in Release builds, causing crashes during Data subscripting.

**Fix:** Always copy CryptoKit output into fresh contiguous Data:

```swift
// CRASHES in Release builds:
let encrypted = sealedBox.ciphertext + sealedBox.tag

// SAFE in all builds:
var encrypted = Data(sealedBox.ciphertext)
encrypted.append(contentsOf: sealedBox.tag)
```

This affects any code path using AES-GCM encryption followed by Data slicing (e.g., QR export).

### Verification

Signature verification is a pure function of `(public_key, message_hash, signature)`. No secret material is involved, so verification can happen on any device, server, or blockchain node without MPC.

```c
int cbmpc_ecdsa_verify(int curve_code, cbmpc_cmem_t pub_oct,
                       cbmpc_cmem_t hash, cbmpc_cmem_t der_sig);
```

---

## 12. References

### Internal Documentation

- [CB-MPC Visual Guide](./cb-mpc-visual-guide.html) -- Interactive visual walkthrough of MPC concepts
- [Threshold Signing Visual Guide](./cb-mpc-threshold-signing%E2%80%94visual-guide.html) -- Threshold signing flow visualization
- [Feature Plan](./FEATURE_PLAN.md) -- iOS app feature roadmap
- [UX Workflows](./UX_WORKFLOWS.md) -- Complete user flow documentation

### Protocol Specs (Referenced in C++ Source)

| Spec ID | Protocol |
|---------|----------|
| EC-DKG-2P | 2-party distributed key generation |
| EC-Refresh-2P | 2-party key refresh |
| EC-DKG-MP | N-party distributed key generation |
| EC-DKG-Threshold-MP | Threshold distributed key generation |
| ECDSA-2PC-Optimized-KeyGen-2P | ECDSA 2-party key generation with Paillier |
| ECDSA-2PC-Sign-2P | ECDSA 2-party signing |
| ECDSA-MPC-Sign-MP | ECDSA N-party signing with OT |
| Init-Derive-2P | HD key initialization |
| Hard-Derive-2P | Hardened HD derivation |
| VRF-Refresh-2P | Verifiable random function refresh |

### External Standards

- [BIP-32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki) -- Hierarchical Deterministic Wallets
- [BIP-39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki) -- Mnemonic Code for Generating Deterministic Keys
- [BIP-44](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki) -- Multi-Account Hierarchy for Deterministic Wallets
- [BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki) -- Schnorr Signatures for secp256k1

### Source File Index

| Component | Key Files |
|-----------|-----------|
| EC-DKG | `src/cbmpc/protocol/ec_dkg.h`, `ec_dkg.cpp` |
| ECDSA 2-Party | `src/cbmpc/protocol/ecdsa_2p.h`, `ecdsa_2p.cpp` |
| ECDSA N-Party | `src/cbmpc/protocol/ecdsa_mp.h`, `ecdsa_mp.cpp` |
| EdDSA | `src/cbmpc/protocol/eddsa.h`, `eddsa.cpp` |
| Schnorr | `src/cbmpc/protocol/schnorr_2p.h`, `schnorr_mp.h` |
| HD Derivation | `src/cbmpc/protocol/hd_keyset_ecdsa_2p.h`, `hd_tree_bip32.h` |
| Access Structures | `src/cbmpc/crypto/secret_sharing.h` |
| ZK Proofs | `src/cbmpc/zk/zk_ec.h`, `zk_paillier.h`, `zk_pedersen.h` |
| OT | `src/cbmpc/protocol/ot.h` |
| PVE | `src/cbmpc/protocol/pve_ac.h` |
| iOS C API | `src/cbmpc/ios/cbmpc_ios.h` |
| Go ECDSA 2P | `demos-go/cb-mpc-go/api/mpc/ecdsa_2p.go` |
| Go ECDSA MP | `demos-go/cb-mpc-go/api/mpc/ecdsa_mp.go` |
| Go EdDSA MP | `demos-go/cb-mpc-go/api/mpc/eddsa_mp.go` |
| Go Threshold Web | `demos-go/cmd/threshold-ecdsa-web/handlers.go` |
| Go Transport | `demos-go/cb-mpc-go/api/transport/mtls/transport.go` |
| Swift Crypto Engine | `CBMPCNative/CBMPCNative/Models/CBMPCCryptoEngine.swift` |
| Swift Key Store | `CBMPCNative/CBMPCNative/Models/KeyStore.swift` |
| Swift Key Model | `CBMPCNative/CBMPCNative/Models/ManagedKeyModel.swift` |
