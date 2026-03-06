#include "cbmpc_ios.h"

#include <cbmpc/protocol/agree_random.h>
#include <cbmpc/protocol/mpc_job.h>
#include <cbmpc/ffi/cmem_adapter.h>

using namespace coinbase;
using namespace coinbase::mpc;

extern "C" {

int cbmpc_agree_random(cbmpc_job2p_t* j, int bitlen, cbmpc_cmem_t* out) {
  if (!j || !j->opaque || !out || bitlen <= 0) return -1;

  try {
    job_2p_t* job = static_cast<job_2p_t*>(j->opaque);
    buf_t result;

    error_t err = agree_random(*job, bitlen, result);
    if (err) return err;

    void* buf = cgo_malloc(result.size());
    if (!buf) return -1;

    memcpy(buf, result.data(), result.size());
    out->data = buf;
    out->size = result.size();
    return 0;
  } catch (...) {
    return -1;
  }
}

}  // extern "C"
