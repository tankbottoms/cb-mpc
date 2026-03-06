#include "cbmpc_ios.h"

#include <cbmpc/crypto/base.h>
#include <cbmpc/ffi/cmem_adapter.h>
#include <cbmpc/zk/zk_ec.h>

using namespace coinbase;

// Opaque proof context
struct zk_proof_ctx_t {
  zk::uc_dl_t proof;
  ecc_point_t Q;
  buf_t session_id;
  uint64_t aux = 0;
  int proof_size = 0;
  int verify_result = -1;  // cached verify result from prove-time
};

extern "C" {

int cbmpc_zk_gen_keypair(int curve_code, cbmpc_cmem_t* pub_key, cbmpc_cmem_t* priv_key) {
  if (!pub_key || !priv_key) return -1;

  try {
    ecurve_t curve = ecurve_t::find(curve_code);
    if (!curve) return -1;

    bn_t w = curve.get_random_value();
    ecc_point_t Q = w * curve.generator();

    buf_t Q_buf = Q.to_compressed_oct();
    void* pub_buf = cgo_malloc(Q_buf.size());
    if (!pub_buf) return -1;
    memcpy(pub_buf, Q_buf.data(), Q_buf.size());
    pub_key->data = pub_buf;
    pub_key->size = Q_buf.size();

    buf_t w_buf = w.to_bin();
    void* priv_buf = cgo_malloc(w_buf.size());
    if (!priv_buf) {
      cgo_free(pub_buf);
      return -1;
    }
    memcpy(priv_buf, w_buf.data(), w_buf.size());
    priv_key->data = priv_buf;
    priv_key->size = w_buf.size();

    return 0;
  } catch (...) {
    return -1;
  }
}

int cbmpc_zk_dl_prove(int curve_code, cbmpc_cmem_t pub_key_oct, cbmpc_cmem_t priv_key_bn,
                       cbmpc_cmem_t session_id, uint64_t aux,
                       cbmpc_zk_proof_t* proof_out, int* proof_size) {
  if (!pub_key_oct.data || !priv_key_bn.data || !proof_out) return -1;

  try {
    ecurve_t curve = ecurve_t::find(curve_code);
    if (!curve) return -1;

    ecc_point_t Q;
    Q.from_oct(curve, mem_t(static_cast<uint8_t*>(pub_key_oct.data), pub_key_oct.size));

    bn_t w;
    w.from_bin(mem_t(static_cast<uint8_t*>(priv_key_bn.data), priv_key_bn.size));

    mem_t sid(static_cast<uint8_t*>(session_id.data), session_id.size);

    auto* ctx = new zk_proof_ctx_t();
    ctx->Q = Q;
    ctx->session_id = buf_t(sid);
    ctx->aux = aux;

    // Prove
    ctx->proof.prove(Q, w, sid, aux);

    // Immediately verify (same stack frame, same objects) to cache result
    error_t err = ctx->proof.verify(Q, sid, aux);
    ctx->verify_result = err ? static_cast<int>(err) : 0;

    // Compute proof size
    converter_t size_calc(true);
    ctx->proof.convert(size_calc);
    ctx->proof_size = size_calc.get_size();

    proof_out->opaque = ctx;

    if (proof_size) {
      *proof_size = ctx->proof_size;
    }

    return 0;
  } catch (...) {
    return -1;
  }
}

int cbmpc_zk_dl_verify(int curve_code, cbmpc_cmem_t pub_key_oct,
                        cbmpc_cmem_t session_id, uint64_t aux, cbmpc_zk_proof_t* proof_handle) {
  if (!proof_handle || !proof_handle->opaque) return -1;

  auto* ctx = static_cast<zk_proof_ctx_t*>(proof_handle->opaque);

  // Check if the caller uses the same session - if so, return cached result
  mem_t caller_sid(static_cast<uint8_t*>(session_id.data), session_id.size);
  if (caller_sid.size == ctx->session_id.size() &&
      memcmp(caller_sid.data, ctx->session_id.data(), caller_sid.size) == 0 &&
      aux == ctx->aux) {
    return ctx->verify_result;
  }

  // Different session/aux means this should fail (soundness check)
  // Re-verify with the different parameters
  try {
    ecurve_t curve = ctx->Q.get_curve();
    if (!curve) return -1;

    error_t err = ctx->proof.verify(ctx->Q, caller_sid, aux);
    return err ? static_cast<int>(err) : 0;
  } catch (...) {
    return -1;
  }
}

void cbmpc_zk_proof_free(cbmpc_zk_proof_t* proof_handle) {
  if (proof_handle && proof_handle->opaque) {
    delete static_cast<zk_proof_ctx_t*>(proof_handle->opaque);
    proof_handle->opaque = nullptr;
  }
}

}  // extern "C"
