#include "cbmpc_ios.h"

#include <iostream>
#include <cstdlib>
#include <memory>
#include <string_view>
#include <vector>

#include <cbmpc/protocol/ecdsa_2p.h>
#include <cbmpc/protocol/mpc_job_session.h>
#include <cbmpc/ffi/cmem_adapter.h>
#include <cbmpc/crypto/base_ecc.h>

using namespace coinbase;
using namespace coinbase::mpc;

namespace {
constexpr int SUCCESS_CODE = 0;
constexpr int ERROR_CODE = -1;
constexpr int PARAM_ERROR_CODE = -2;

// Validate party names
bool validate_party_names(const char* const* pnames, int count) noexcept {
  if (!pnames) return false;
  for (int i = 0; i < count; ++i) {
    if (!pnames[i] || std::string_view(pnames[i]).empty()) {
      return false;
    }
  }
  return true;
}

// Validate and dereference callbacks
const cbmpc_transport_t& validate_and_deref_callbacks(const cbmpc_transport_t* callbacks_ptr) {
  if (!callbacks_ptr) {
    throw std::invalid_argument("callbacks_ptr cannot be null");
  }
  if (!callbacks_ptr->send_fn || !callbacks_ptr->receive_fn || !callbacks_ptr->receive_all_fn) {
    throw std::invalid_argument("all callback functions must be provided");
  }
  return *callbacks_ptr;
}

void* validate_ctx_ptr(void* ctx) {
  if (!ctx) {
    throw std::invalid_argument("ctx cannot be null");
  }
  return ctx;
}

// Callback-based transport implementation
class callback_data_transport_t : public data_transport_interface_t {
 private:
  const cbmpc_transport_t callbacks;
  void* const ctx;

 public:
  callback_data_transport_t(const cbmpc_transport_t* callbacks_ptr, void* ctx_ptr)
      : callbacks(validate_and_deref_callbacks(callbacks_ptr)), ctx(validate_ctx_ptr(ctx_ptr)) {}

  error_t send(const party_idx_t receiver, mem_t msg) override {
    cbmpc_cmem_t cmsg{msg.data, msg.size};
    int result = callbacks.send_fn(ctx, receiver, cmsg);
    return error_t(result);
  }

  error_t receive(const party_idx_t sender, buf_t& msg) override {
    cbmpc_cmem_t cmsg{nullptr, 0};
    error_t rv = UNINITIALIZED_ERROR;
    if (rv = error_t(callbacks.receive_fn(ctx, sender, &cmsg))) return rv;
    // Cast cbmpc_cmem_t to cmem_t for adapter function
    cmem_t internal_cmem{static_cast<uint8_t*>(cmsg.data), cmsg.size};
    msg = coinbase::ffi::copy_from_cmem_and_free(internal_cmem);
    return SUCCESS;
  }

  error_t receive_all(const std::vector<party_idx_t>& senders, std::vector<buf_t>& msgs) override {
    const auto n = static_cast<int>(senders.size());
    if (n == 0) {
      msgs.clear();
      return SUCCESS;
    }

    std::vector<int> c_senders;
    c_senders.reserve(n);
    for (const auto sender : senders) {
      c_senders.push_back(sender);
    }

    cbmpc_cmems_t cmsgs{0, nullptr, nullptr};
    const int result = callbacks.receive_all_fn(ctx, const_cast<int*>(c_senders.data()), n, &cmsgs);
    if (error_t rv = error_t(result)) {
      msgs.clear();
      return rv;
    }

    // Cast cbmpc_cmems_t to cmems_t for adapter function
    cmems_t internal_cmems{cmsgs.count, static_cast<uint8_t*>(cmsgs.data), cmsgs.sizes};
    msgs = coinbase::ffi::bufs_from_cmems(internal_cmems);
    cgo_free(cmsgs.data);
    cgo_free(cmsgs.sizes);
    return SUCCESS;
  }
};
}  // namespace

extern "C" {

void cbmpc_job2p_free(cbmpc_job2p_t* ptr) {
  if (!ptr) return;

  if (ptr->opaque) {
    try {
      delete static_cast<job_2p_t*>(ptr->opaque);
    } catch (const std::exception& e) {
      std::cerr << "Error freeing job_2p: " << e.what() << std::endl;
    }
    ptr->opaque = nullptr;
  }
  delete ptr;
}

cbmpc_job2p_t* cbmpc_job2p_new(const cbmpc_transport_t* callbacks, void* ctx,
                                int role, const char* const* pnames, int pname_count) {
  // Validate inputs
  if (pname_count != 2) {
    std::cerr << "Error: expected exactly 2 pnames, got " << pname_count << std::endl;
    return nullptr;
  }

  if (!callbacks || !ctx) {
    std::cerr << "Error: null parameters passed to cbmpc_job2p_new" << std::endl;
    return nullptr;
  }

  if (!validate_party_names(pnames, pname_count)) {
    std::cerr << "Error: invalid party names" << std::endl;
    return nullptr;
  }

  try {
    auto data_transport_ptr = std::make_shared<callback_data_transport_t>(callbacks, ctx);
    auto job_impl = std::make_unique<job_2p_t>(
        party_t(role), std::string(pnames[0]), std::string(pnames[1]), data_transport_ptr);

    auto result = std::make_unique<cbmpc_job2p_t>();
    result->opaque = job_impl.release();
    return result.release();

  } catch (const std::exception& e) {
    std::cerr << "Error creating job_2p: " << e.what() << std::endl;
    return nullptr;
  }
}

int cbmpc_job2p_role(const cbmpc_job2p_t* job) {
  if (!job || !job->opaque) return -1;
  return static_cast<int>(static_cast<const job_2p_t*>(job->opaque)->get_party_idx());
}

int cbmpc_ecdsa_verify(int curve_code, cbmpc_cmem_t pub_oct,
                        cbmpc_cmem_t hash, cbmpc_cmem_t der_sig) {
  using namespace coinbase::crypto;

  if (!pub_oct.data || !hash.data || !der_sig.data) return -1;

  try {
    ecurve_t curve = ecurve_t::find(curve_code);
    if (!curve) return -1;

    ecc_point_t Q;
    mem_t pub_mem{static_cast<const uint8_t*>(pub_oct.data), pub_oct.size};
    if (Q.from_oct(curve, pub_mem)) return -1;

    ecc_pub_key_t pub_key(Q);
    mem_t hash_mem{static_cast<const uint8_t*>(hash.data), hash.size};
    mem_t sig_mem{static_cast<const uint8_t*>(der_sig.data), der_sig.size};

    if (pub_key.verify(hash_mem, sig_mem)) return -1;

    return SUCCESS_CODE;
  } catch (...) {
    return -1;
  }
}

}  // extern "C"
