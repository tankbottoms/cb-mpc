#include "cbmpc_ios.h"

#include <iostream>
#include <memory>
#include <string_view>
#include <vector>

#include <cbmpc/protocol/mpc_job_session.h>
#include <cbmpc/ffi/cmem_adapter.h>
#include <cbmpc/crypto/base_ecc.h>

using namespace coinbase;
using namespace coinbase::mpc;

namespace {

bool validate_party_names_mp(const char* const* pnames, int count) noexcept {
  if (!pnames) return false;
  for (int i = 0; i < count; ++i) {
    if (!pnames[i] || std::string_view(pnames[i]).empty()) return false;
  }
  return true;
}

class mp_callback_data_transport_t : public data_transport_interface_t {
 private:
  const cbmpc_transport_t callbacks;
  void* const ctx;

 public:
  mp_callback_data_transport_t(const cbmpc_transport_t* cb, void* ctx_ptr)
      : callbacks(*cb), ctx(ctx_ptr) {}

  error_t send(const party_idx_t receiver, mem_t msg) override {
    cbmpc_cmem_t cmsg{msg.data, msg.size};
    return error_t(callbacks.send_fn(ctx, receiver, cmsg));
  }

  error_t receive(const party_idx_t sender, buf_t& msg) override {
    cbmpc_cmem_t cmsg{nullptr, 0};
    error_t rv = UNINITIALIZED_ERROR;
    if (rv = error_t(callbacks.receive_fn(ctx, sender, &cmsg))) return rv;
    cmem_t internal{static_cast<uint8_t*>(cmsg.data), cmsg.size};
    msg = coinbase::ffi::copy_from_cmem_and_free(internal);
    return SUCCESS;
  }

  error_t receive_all(const std::vector<party_idx_t>& senders, std::vector<buf_t>& msgs) override {
    const auto n = static_cast<int>(senders.size());
    if (n == 0) { msgs.clear(); return SUCCESS; }
    std::vector<int> c_senders;
    c_senders.reserve(n);
    for (const auto s : senders) c_senders.push_back(s);
    cbmpc_cmems_t cmsgs{0, nullptr, nullptr};
    int result = callbacks.receive_all_fn(ctx, c_senders.data(), n, &cmsgs);
    if (error_t rv = error_t(result)) { msgs.clear(); return rv; }
    cmems_t internal{cmsgs.count, static_cast<uint8_t*>(cmsgs.data), cmsgs.sizes};
    msgs = coinbase::ffi::bufs_from_cmems(internal);
    cgo_free(cmsgs.data);
    cgo_free(cmsgs.sizes);
    return SUCCESS;
  }
};

}  // namespace

extern "C" {

cbmpc_jobmp_t* cbmpc_jobmp_new(const cbmpc_transport_t* callbacks, void* ctx,
                                int party_count, int role,
                                const char* const* pnames, int pname_count) {
  if (pname_count != party_count || party_count <= 0) {
    std::cerr << "Error: pname_count must equal party_count" << std::endl;
    return nullptr;
  }
  if (!callbacks || !ctx) {
    std::cerr << "Error: null parameters" << std::endl;
    return nullptr;
  }
  if (!validate_party_names_mp(pnames, pname_count)) {
    std::cerr << "Error: invalid party names" << std::endl;
    return nullptr;
  }

  try {
    auto transport = std::make_shared<mp_callback_data_transport_t>(callbacks, ctx);
    std::vector<crypto::pname_t> names;
    names.reserve(party_count);
    for (int i = 0; i < party_count; ++i) names.emplace_back(pnames[i]);
    auto job = std::make_unique<job_mp_t>(party_idx_t(role), std::move(names), transport);
    auto result = std::make_unique<cbmpc_jobmp_t>();
    result->opaque = job.release();
    return result.release();
  } catch (const std::exception& e) {
    std::cerr << "Error creating job_mp: " << e.what() << std::endl;
    return nullptr;
  }
}

void cbmpc_jobmp_free(cbmpc_jobmp_t* job) {
  if (!job) return;
  if (job->opaque) {
    try { delete static_cast<job_mp_t*>(job->opaque); }
    catch (const std::exception& e) { std::cerr << "Error freeing job_mp: " << e.what() << std::endl; }
    job->opaque = nullptr;
  }
  delete job;
}

int cbmpc_jobmp_role(const cbmpc_jobmp_t* job) {
  if (!job || !job->opaque) return -1;
  return static_cast<int>(static_cast<const job_mp_t*>(job->opaque)->get_party_idx());
}

int cbmpc_jobmp_n_parties(const cbmpc_jobmp_t* job) {
  if (!job || !job->opaque) return -1;
  return static_cast<int>(static_cast<const job_mp_t*>(job->opaque)->get_n_parties());
}

}  // extern "C"
