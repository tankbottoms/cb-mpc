#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/* ==================== Memory Management ==================== */
void* cbmpc_malloc(int size);
void  cbmpc_free(void* ptr);

/* ==================== Type Definitions ==================== */

/* cmem_t matches definition in cbmpc/ffi/cmem_adapter.h */
typedef struct {
  void* data;
  int   size;
} cbmpc_cmem_t;

/* cmems_t matches definition in cbmpc/ffi/cmem_adapter.h */
typedef struct {
  int   count;
  void* data;     /* flat contiguous buffer */
  int*  sizes;    /* array of size_t for each element */
} cbmpc_cmems_t;

/* ==================== Transport Callbacks ==================== */

/* Transport callback function types
 * ctx: opaque context pointer (Swift transport implementation)
 * receiver/sender: party index (0 or 1 for 2-party)
 * message/out_message: data to send/receive
 * senders/count: array of party indices and count for receive_all
 * out: output parameter for received messages
 *
 * Return: 0 on success, non-zero on error
 */

typedef int (*cbmpc_send_f)(void* ctx, int receiver, cbmpc_cmem_t message);
typedef int (*cbmpc_receive_f)(void* ctx, int sender, cbmpc_cmem_t* out_message);
typedef int (*cbmpc_receive_all_f)(void* ctx, int* senders, int count, cbmpc_cmems_t* out);

typedef struct {
  cbmpc_send_f        send_fn;
  cbmpc_receive_f     receive_fn;
  cbmpc_receive_all_f receive_all_fn;
} cbmpc_transport_t;

/* ==================== Job Management (2-Party MPC) ==================== */

typedef struct { void* opaque; } cbmpc_job2p_t;

/* Create a new 2-party MPC job
 * callbacks: transport callback functions
 * ctx: opaque context pointer (passed to callbacks)
 * role: party index (0 or 1)
 * pnames: array of party names (["Alice", "Bob"] for example)
 * pname_count: must be 2
 * Returns: pointer to new job, or NULL on error
 */
cbmpc_job2p_t* cbmpc_job2p_new(const cbmpc_transport_t* callbacks, void* ctx,
                                int role, const char* const* pnames, int pname_count);

/* Free a job and all associated resources */
void cbmpc_job2p_free(cbmpc_job2p_t* job);

/* Get the role (party index) of this job */
int  cbmpc_job2p_role(const cbmpc_job2p_t* job);

/* ==================== ECDSA 2-Party DKG, Sign, Refresh ==================== */

typedef struct { void* opaque; } cbmpc_ecdsa2p_key_t;

/* Distributed Key Generation - creates a shared key pair
 * job: 2-party job
 * curve_code: OpenSSL NID for curve (714 = secp256k1, 415 = prime256v1, etc.)
 * out: [output] pointer to newly created key
 * Returns: 0 on success, non-zero on error
 */
int  cbmpc_ecdsa2p_dkg(cbmpc_job2p_t* job, int curve_code, cbmpc_ecdsa2p_key_t* out);

/* Key refresh - generates new share randomness without changing public key
 * job: 2-party job
 * key: existing key share to refresh
 * out: [output] newly refreshed key share
 * Returns: 0 on success, non-zero on error
 */
int  cbmpc_ecdsa2p_refresh(cbmpc_job2p_t* job, cbmpc_ecdsa2p_key_t* key,
                            cbmpc_ecdsa2p_key_t* out);

/* Sign multiple messages using the shared key
 * job: 2-party job
 * sid: session ID (should be unique per signing session)
 * key: key share to use for signing
 * msgs: array of message hashes to sign (typically 32-byte SHA256 digests)
 * out_sigs: [output] array of DER-encoded signatures
 * Returns: 0 on success, non-zero on error
 */
int  cbmpc_ecdsa2p_sign(cbmpc_job2p_t* job, cbmpc_cmem_t sid,
                         cbmpc_ecdsa2p_key_t* key, cbmpc_cmems_t msgs,
                         cbmpc_cmems_t* out_sigs);

/* Free a key share */
void cbmpc_ecdsa2p_key_free(cbmpc_ecdsa2p_key_t key);

/* Get the role (party index) associated with this key share */
int  cbmpc_ecdsa2p_key_role(const cbmpc_ecdsa2p_key_t* key);

/* Get the OpenSSL curve NID for this key */
int  cbmpc_ecdsa2p_key_curve_code(const cbmpc_ecdsa2p_key_t* key);

/* ==================== Key Serialization ==================== */

/* Serialize key to bytes (for persistence)
 * key: key share to serialize
 * Returns: serialized bytes (caller must free with cbmpc_free)
 */
cbmpc_cmem_t cbmpc_ecdsa2p_key_serialize(const cbmpc_ecdsa2p_key_t* key);

/* Deserialize key from bytes
 * data: serialized key bytes
 * out: [output] deserialized key
 * Returns: 0 on success, non-zero on error
 */
int          cbmpc_ecdsa2p_key_deserialize(cbmpc_cmem_t data, cbmpc_ecdsa2p_key_t* out);

/* ==================== Key Public Data ==================== */

/* Extract public key as 33-byte compressed SEC1 point
 * key: key share
 * Returns: compressed public key bytes (caller must free with cbmpc_free)
 */
cbmpc_cmem_t cbmpc_ecdsa2p_key_pubkey(const cbmpc_ecdsa2p_key_t* key);

/* ==================== HD Keyset (BIP32 Hierarchical Deterministic) ==================== */

typedef struct { void* opaque; } cbmpc_hd_key_t;

/* Create a hierarchical deterministic keyset
 * job: 2-party job
 * curve_code: OpenSSL NID for curve
 * out: [output] newly created HD key
 * Returns: 0 on success, non-zero on error
 */
int  cbmpc_hd_ecdsa2p_dkg(cbmpc_job2p_t* job, int curve_code, cbmpc_hd_key_t* out);

/* Derive a child key using BIP44 path
 * job: 2-party job
 * key: HD keyset to derive from
 * path: array of BIP44 path indices
 * path_len: length of path array
 * out_child: [output] derived child key (standard ECDSA key, not HD)
 * Returns: 0 on success, non-zero on error
 */
int  cbmpc_hd_ecdsa2p_derive(cbmpc_job2p_t* job, cbmpc_hd_key_t* key,
                               const int* path, int path_len,
                               cbmpc_ecdsa2p_key_t* out_child);

/* Refresh HD keyset randomness
 * job: 2-party job
 * key: existing HD keyset
 * out: [output] refreshed HD keyset
 * Returns: 0 on success, non-zero on error
 */
int  cbmpc_hd_ecdsa2p_refresh(cbmpc_job2p_t* job, cbmpc_hd_key_t* key,
                                cbmpc_hd_key_t* out);

/* Free an HD keyset */
void cbmpc_hd_key_free(cbmpc_hd_key_t key);

/* ==================== AgreeRandom (2-Party Shared Randomness) ==================== */

/* Generate shared random bytes using 2-party commit-reveal protocol
 * job: 2-party job
 * bitlen: number of random bits to generate (e.g., 128, 256)
 * out: [output] shared random bytes (caller must free with cbmpc_free)
 * Returns: 0 on success, non-zero on error
 */
int cbmpc_agree_random(cbmpc_job2p_t* job, int bitlen, cbmpc_cmem_t* out);

/* ==================== ZK Proofs (UC-secure Discrete Log) ==================== */

typedef struct { void* opaque; } cbmpc_zk_proof_t;

/* Generate a random EC keypair for ZK proof testing
 * curve_code: OpenSSL NID for curve
 * pub_key: [output] compressed SEC1 public key (caller must free)
 * priv_key: [output] private key scalar as big-endian bytes (caller must free)
 * Returns: 0 on success
 */
int cbmpc_zk_gen_keypair(int curve_code, cbmpc_cmem_t* pub_key, cbmpc_cmem_t* priv_key);

/* Prove knowledge of discrete log: Q = w * G (Fischlin UC-DL)
 * curve_code: OpenSSL NID for curve
 * pub_key_oct: compressed SEC1 public key Q
 * priv_key_bn: private key scalar w as big-endian bytes
 * session_id: unique session identifier
 * aux: auxiliary input (e.g., 0)
 * proof_out: [output] opaque proof handle (caller must free with cbmpc_zk_proof_free)
 * proof_size: [output] proof size in bytes (optional, may be NULL)
 * Returns: 0 on success
 */
int cbmpc_zk_dl_prove(int curve_code, cbmpc_cmem_t pub_key_oct, cbmpc_cmem_t priv_key_bn,
                       cbmpc_cmem_t session_id, uint64_t aux,
                       cbmpc_zk_proof_t* proof_out, int* proof_size);

/* Verify a UC-DL proof
 * curve_code: OpenSSL NID for curve
 * pub_key_oct: compressed SEC1 public key Q
 * session_id: must match the session_id used in prove
 * aux: must match the aux used in prove
 * proof: opaque proof handle from cbmpc_zk_dl_prove
 * Returns: 0 if valid, non-zero if invalid
 */
int cbmpc_zk_dl_verify(int curve_code, cbmpc_cmem_t pub_key_oct,
                        cbmpc_cmem_t session_id, uint64_t aux, cbmpc_zk_proof_t* proof);

/* Free a ZK proof handle */
void cbmpc_zk_proof_free(cbmpc_zk_proof_t* proof);

/* ==================== Stateless Signature Verification ==================== */

/* Verify ECDSA signature (no key material needed)
 * curve_code: OpenSSL NID for curve
 * pub_oct: public key as uncompressed or compressed SEC1 bytes
 * hash: message hash (32 bytes for SHA256)
 * der_sig: signature in DER encoding
 * Returns: 0 if signature valid, non-zero if invalid
 */
int cbmpc_ecdsa_verify(int curve_code, cbmpc_cmem_t pub_oct,
                        cbmpc_cmem_t hash, cbmpc_cmem_t der_sig);

#ifdef __cplusplus
}
#endif
