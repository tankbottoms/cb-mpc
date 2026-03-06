#include "cbmpc_ios.h"

#include <memory>

#include <cbmpc/core/buf.h>
#include <cbmpc/crypto/base.h>
#include <cbmpc/protocol/ecdsa_2p.h>
#include <cbmpc/protocol/mpc_job_session.h>
#include <cbmpc/ffi/cmem_adapter.h>

using namespace coinbase;
using namespace coinbase::mpc;

extern "C" {

int cbmpc_ecdsa2p_dkg(cbmpc_job2p_t* j, int curve_code, cbmpc_ecdsa2p_key_t* k) {
  if (!j || !j->opaque || !k) return -1;

  try {
    job_2p_t* job = static_cast<job_2p_t*>(j->opaque);
    ecurve_t curve = ecurve_t::find(curve_code);
    if (!curve) return -1;  // Invalid curve code

    ecdsa2pc::key_t* key = new ecdsa2pc::key_t();
    error_t err = ecdsa2pc::dkg(*job, curve, *key);
    if (err) {
      delete key;
      return err;
    }

    k->opaque = key;
    return 0;
  } catch (...) {
    return -1;
  }
}

int cbmpc_ecdsa2p_refresh(cbmpc_job2p_t* j, cbmpc_ecdsa2p_key_t* k, cbmpc_ecdsa2p_key_t* nk) {
  if (!j || !j->opaque || !k || !k->opaque || !nk) return -1;

  try {
    job_2p_t* job = static_cast<job_2p_t*>(j->opaque);
    ecdsa2pc::key_t* key = static_cast<ecdsa2pc::key_t*>(k->opaque);
    ecdsa2pc::key_t* new_key = new ecdsa2pc::key_t();

    error_t err = ecdsa2pc::refresh(*job, *key, *new_key);
    if (err) {
      delete new_key;
      return err;
    }

    nk->opaque = new_key;
    return 0;
  } catch (...) {
    return -1;
  }
}

int cbmpc_ecdsa2p_sign(cbmpc_job2p_t* j, cbmpc_cmem_t sid_mem, cbmpc_ecdsa2p_key_t* k,
                        cbmpc_cmems_t msgs, cbmpc_cmems_t* sigs) {
  if (!j || !j->opaque || !k || !k->opaque || !msgs.data || msgs.count <= 0 || !sigs) return -1;

  try {
    job_2p_t* job = static_cast<job_2p_t*>(j->opaque);
    ecdsa2pc::key_t* key = static_cast<ecdsa2pc::key_t*>(k->opaque);

    // Create session ID from input buffer
    buf_t sid(static_cast<uint8_t*>(sid_mem.data), sid_mem.size);

    // Reconstruct message vector from cbmpc_cmems_t
    std::vector<mem_t> messages;
    const uint8_t* p = static_cast<const uint8_t*>(msgs.data);
    for (int i = 0; i < msgs.count; i++) {
      int len = msgs.sizes ? msgs.sizes[i] : 0;
      if (len > 0) {
        messages.push_back(mem_t(p, len));
        p += len;
      } else {
        messages.push_back(mem_t(nullptr, 0));
      }
    }

    // Perform signing
    std::vector<buf_t> signatures;
    error_t err = ecdsa2pc::sign_batch(*job, sid, *key, messages, signatures);
    if (err) return err;

    // Convert signature buffers to cbmpc_cmems_t format
    // Flatten signatures into contiguous buffer
    int total_size = 0;
    std::vector<int> sig_sizes;
    for (const auto& sig : signatures) {
      sig_sizes.push_back(sig.size());
      total_size += sig.size();
    }

    if (total_size == 0) {
      sigs->count = 0;
      sigs->data = nullptr;
      sigs->sizes = nullptr;
      return 0;
    }

    // Allocate flat buffer and size array
    void* flat_buffer = cgo_malloc(total_size);
    int* size_array = (int*)cgo_malloc(signatures.size() * sizeof(int));

    if (!flat_buffer || !size_array) {
      cgo_free(flat_buffer);
      cgo_free(size_array);
      return -1;
    }

    // Copy signatures into flat buffer
    uint8_t* dst = static_cast<uint8_t*>(flat_buffer);
    for (size_t i = 0; i < signatures.size(); i++) {
      memcpy(dst, signatures[i].data(), signatures[i].size());
      size_array[i] = signatures[i].size();
      dst += signatures[i].size();
    }

    sigs->count = signatures.size();
    sigs->data = flat_buffer;
    sigs->sizes = size_array;
    return 0;
  } catch (...) {
    return -1;
  }
}

void cbmpc_ecdsa2p_key_free(cbmpc_ecdsa2p_key_t ctx) {
  if (ctx.opaque) {
    delete static_cast<ecdsa2pc::key_t*>(ctx.opaque);
  }
}

int cbmpc_ecdsa2p_key_role(const cbmpc_ecdsa2p_key_t* key) {
  if (key == NULL || key->opaque == NULL) {
    return -1;
  }
  ecdsa2pc::key_t* k = static_cast<ecdsa2pc::key_t*>(key->opaque);
  return static_cast<int>(k->role);
}

cbmpc_cmem_t cbmpc_ecdsa2p_key_pubkey(const cbmpc_ecdsa2p_key_t* key) {
  if (key == NULL || key->opaque == NULL) {
    return cbmpc_cmem_t{nullptr, 0};
  }
  try {
    ecdsa2pc::key_t* k = static_cast<ecdsa2pc::key_t*>(key->opaque);
    // Serialize public key Q to compressed SEC1 format (33 bytes for secp256k1)
    buf_t Q_buf = k->Q.to_compressed_oct();

    // Allocate and copy result
    void* result = cgo_malloc(Q_buf.size());
    if (!result) return cbmpc_cmem_t{nullptr, 0};

    memcpy(result, Q_buf.data(), Q_buf.size());
    return cbmpc_cmem_t{result, Q_buf.size()};
  } catch (...) {
    return cbmpc_cmem_t{nullptr, 0};
  }
}

cbmpc_cmem_t cbmpc_ecdsa2p_key_serialize(const cbmpc_ecdsa2p_key_t* key) {
  if (key == NULL || key->opaque == NULL) {
    return cbmpc_cmem_t{nullptr, 0};
  }
  try {
    ecdsa2pc::key_t* k = static_cast<ecdsa2pc::key_t*>(key->opaque);

    // Calculate serialization size first (write=true with null pointer = calc size mode)
    converter_t size_calc(true);
    uint32_t role_val = static_cast<uint32_t>(k->role);
    size_calc.convert(role_val);
    size_calc.convert(k->curve);
    size_calc.convert(k->Q);
    size_calc.convert(k->x_share);
    size_calc.convert(k->c_key);
    size_calc.convert(k->paillier);

    int size = size_calc.get_size();
    if (size <= 0) return cbmpc_cmem_t{nullptr, 0};

    // Allocate buffer for serialization
    uint8_t* buffer = static_cast<uint8_t*>(cgo_malloc(size));
    if (!buffer) return cbmpc_cmem_t{nullptr, 0};

    // Serialize into buffer
    converter_t serializer(buffer);
    serializer.convert(role_val);
    serializer.convert(k->curve);
    serializer.convert(k->Q);
    serializer.convert(k->x_share);
    serializer.convert(k->c_key);
    serializer.convert(k->paillier);

    if (serializer.is_error()) {
      cgo_free(buffer);
      return cbmpc_cmem_t{nullptr, 0};
    }

    return cbmpc_cmem_t{buffer, serializer.get_size()};
  } catch (...) {
    return cbmpc_cmem_t{nullptr, 0};
  }
}

int cbmpc_ecdsa2p_key_deserialize(cbmpc_cmem_t data, cbmpc_ecdsa2p_key_t* out) {
  if (out == NULL || data.data == NULL || data.size == 0) {
    return -1;
  }
  try {
    buf_t buf(static_cast<uint8_t*>(data.data), data.size);
    ecdsa2pc::key_t* key = new ecdsa2pc::key_t();

    converter_t deserializer(buf);
    uint32_t role_val;
    deserializer.convert(role_val);
    deserializer.convert(key->curve);
    deserializer.convert(key->Q);
    deserializer.convert(key->x_share);
    deserializer.convert(key->c_key);
    deserializer.convert(key->paillier);

    if (deserializer.is_error()) {
      delete key;
      return -1;
    }

    key->role = static_cast<party_t>(role_val);
    *out = cbmpc_ecdsa2p_key_t{key};
    return 0;
  } catch (...) {
    return -1;
  }
}

int cbmpc_ecdsa2p_key_curve_code(const cbmpc_ecdsa2p_key_t* key) {
  if (key == NULL || key->opaque == NULL) {
    return -1;
  }
  ecdsa2pc::key_t* k = static_cast<ecdsa2pc::key_t*>(key->opaque);
  return k->curve.get_openssl_code();
}

}  // extern "C"
