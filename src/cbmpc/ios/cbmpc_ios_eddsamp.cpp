#include "cbmpc_ios.h"

#include <memory>

#include <cbmpc/core/buf.h>
#include <cbmpc/protocol/eddsa.h>
#include <cbmpc/protocol/mpc_job_session.h>
#include <cbmpc/ffi/cmem_adapter.h>

using namespace coinbase;
using namespace coinbase::mpc;

extern "C" {

int cbmpc_eddsamp_sign(cbmpc_jobmp_t* job, cbmpc_eckey_mp_t* key,
                        cbmpc_cmem_t msg_mem, int sig_receiver, cbmpc_cmem_t* out_sig) {
  if (!job || !job->opaque || !key || !key->opaque || !out_sig) return -1;

  job_mp_t* j = static_cast<job_mp_t*>(job->opaque);
  eddsampc::key_t* k = static_cast<eddsampc::key_t*>(key->opaque);

  mem_t msg_raw{static_cast<const uint8_t*>(msg_mem.data), msg_mem.size};
  buf_t msg(msg_raw);
  buf_t sig;

  error_t err = eddsampc::sign(*j, *k, msg, party_idx_t(sig_receiver), sig);
  if (err) return err;

  cmem_t internal = coinbase::ffi::copy_to_cmem(sig);
  out_sig->data = internal.data;
  out_sig->size = internal.size;
  return 0;
}

}  // extern "C"
