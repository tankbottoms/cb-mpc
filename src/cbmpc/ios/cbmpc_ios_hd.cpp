#include "cbmpc_ios.h"

#include <memory>

#include <cbmpc/core/buf.h>
#include <cbmpc/crypto/base.h>
#include <cbmpc/protocol/ecdsa_2p.h>
#include <cbmpc/protocol/hd_keyset_ecdsa_2p.h>
#include <cbmpc/protocol/hd_tree_bip32.h>
#include <cbmpc/protocol/mpc_job_session.h>
#include <cbmpc/ffi/cmem_adapter.h>

using namespace coinbase;
using namespace coinbase::mpc;

extern "C" {

int cbmpc_hd_ecdsa2p_dkg(cbmpc_job2p_t* j, int curve_code, cbmpc_hd_key_t* out) {
  if (!j || !j->opaque || !out) return -1;

  try {
    job_2p_t* job = static_cast<job_2p_t*>(j->opaque);
    ecurve_t curve = ecurve_t::find(curve_code);
    if (!curve) return -1;

    key_share_ecdsa_hdmpc_2p_t* key = new key_share_ecdsa_hdmpc_2p_t();

    error_t err = key_share_ecdsa_hdmpc_2p_t::dkg(*job, curve, *key);
    if (err) {
      delete key;
      return err;
    }

    out->opaque = key;
    return 0;
  } catch (...) {
    return -1;
  }
}

int cbmpc_hd_ecdsa2p_derive(cbmpc_job2p_t* j, cbmpc_hd_key_t* key,
                             const int* path, int path_len,
                             cbmpc_ecdsa2p_key_t* out_child) {
  if (!j || !j->opaque || !key || !key->opaque || !path || path_len <= 0 || !out_child) {
    return -1;
  }

  try {
    job_2p_t* job = static_cast<job_2p_t*>(j->opaque);
    key_share_ecdsa_hdmpc_2p_t* hd_key = static_cast<key_share_ecdsa_hdmpc_2p_t*>(key->opaque);

    // Build BIP32 path from array
    bip32_path_t bip_path;
    for (int i = 0; i < path_len; i++) {
      bip_path.append(static_cast<uint32_t>(path[i]));
    }

    // Create paths vector (we're deriving just one key for now)
    std::vector<bip32_path_t> paths;
    paths.push_back(bip_path);

    // Perform derivation
    buf_t sid;  // Session ID (empty for single derivation)
    std::vector<ecdsa2pc::key_t> derived_keys(paths.size());

    error_t err = key_share_ecdsa_hdmpc_2p_t::derive_keys(*job, *hd_key, bip_path, paths, sid, derived_keys);
    if (err) {
      return err;
    }

    if (derived_keys.empty()) {
      return -1;
    }

    // Return first derived key
    ecdsa2pc::key_t* child_key = new ecdsa2pc::key_t(derived_keys[0]);
    out_child->opaque = child_key;
    return 0;
  } catch (...) {
    return -1;
  }
}

int cbmpc_hd_ecdsa2p_refresh(cbmpc_job2p_t* j, cbmpc_hd_key_t* key, cbmpc_hd_key_t* out) {
  if (!j || !j->opaque || !key || !key->opaque || !out) return -1;

  try {
    job_2p_t* job = static_cast<job_2p_t*>(j->opaque);
    key_share_ecdsa_hdmpc_2p_t* hd_key = static_cast<key_share_ecdsa_hdmpc_2p_t*>(key->opaque);
    key_share_ecdsa_hdmpc_2p_t* new_hd_key = new key_share_ecdsa_hdmpc_2p_t();

    error_t err = key_share_ecdsa_hdmpc_2p_t::refresh(*job, *hd_key, *new_hd_key);
    if (err) {
      delete new_hd_key;
      return err;
    }

    out->opaque = new_hd_key;
    return 0;
  } catch (...) {
    return -1;
  }
}

void cbmpc_hd_key_free(cbmpc_hd_key_t key) {
  if (key.opaque) {
    delete static_cast<key_share_ecdsa_hdmpc_2p_t*>(key.opaque);
  }
}

}  // extern "C"
