#include "cbmpc_ios.h"

#include <memory>
#include <set>

#include <cbmpc/core/buf.h>
#include <cbmpc/crypto/base.h>
#include <cbmpc/crypto/secret_sharing.h>
#include <cbmpc/protocol/ec_dkg.h>
#include <cbmpc/protocol/mpc_job_session.h>
#include <cbmpc/ffi/cmem_adapter.h>

using namespace coinbase;
using namespace coinbase::crypto;
using namespace coinbase::mpc;

extern "C" {

int cbmpc_eckey_mp_dkg(cbmpc_jobmp_t* job, cbmpc_curve_t* curve_ref, cbmpc_eckey_mp_t* out) {
  if (!job || !job->opaque || !curve_ref || !curve_ref->opaque || !out) return -1;

  job_mp_t* j = static_cast<job_mp_t*>(job->opaque);
  ecurve_t* curve = static_cast<ecurve_t*>(curve_ref->opaque);

  std::unique_ptr<eckey::key_share_mp_t> key(new eckey::key_share_mp_t());
  buf_t sid;
  error_t err = eckey::key_share_mp_t::dkg(*j, *curve, *key, sid);
  if (err) return err;

  out->opaque = key.release();
  return 0;
}

int cbmpc_eckey_mp_refresh(cbmpc_jobmp_t* job, cbmpc_cmem_t sid_mem,
                            cbmpc_eckey_mp_t* key, cbmpc_eckey_mp_t* out) {
  if (!job || !job->opaque || !key || !key->opaque || !out) return -1;

  job_mp_t* j = static_cast<job_mp_t*>(job->opaque);
  eckey::key_share_mp_t* k = static_cast<eckey::key_share_mp_t*>(key->opaque);

  std::unique_ptr<eckey::key_share_mp_t> new_key(new eckey::key_share_mp_t());
  mem_t sid_raw{static_cast<const uint8_t*>(sid_mem.data), sid_mem.size};
  buf_t sid(sid_raw);
  error_t err = eckey::key_share_mp_t::refresh(*j, sid, *k, *new_key);
  if (err) return err;

  out->opaque = new_key.release();
  return 0;
}

void cbmpc_eckey_mp_free(cbmpc_eckey_mp_t key) {
  if (key.opaque) {
    delete static_cast<eckey::key_share_mp_t*>(key.opaque);
  }
}

cbmpc_cmem_t cbmpc_eckey_mp_pubkey(cbmpc_eckey_mp_t* key) {
  if (!key || !key->opaque) return cbmpc_cmem_t{nullptr, 0};
  eckey::key_share_mp_t* k = static_cast<eckey::key_share_mp_t*>(key->opaque);
  buf_t q_buf = k->Q.to_compressed_oct();
  cmem_t internal = coinbase::ffi::copy_to_cmem(q_buf);
  return cbmpc_cmem_t{internal.data, internal.size};
}

cbmpc_cmem_t cbmpc_eckey_mp_party_name(cbmpc_eckey_mp_t* key) {
  if (!key || !key->opaque) return cbmpc_cmem_t{nullptr, 0};
  eckey::key_share_mp_t* k = static_cast<eckey::key_share_mp_t*>(key->opaque);
  cmem_t internal = coinbase::ffi::copy_to_cmem(coinbase::mem_t(k->party_name));
  return cbmpc_cmem_t{internal.data, internal.size};
}

cbmpc_cmem_t cbmpc_eckey_mp_x_share(cbmpc_eckey_mp_t* key) {
  if (!key || !key->opaque) return cbmpc_cmem_t{nullptr, 0};
  eckey::key_share_mp_t* k = static_cast<eckey::key_share_mp_t*>(key->opaque);
  buf_t x_buf = k->x_share.to_bin(k->curve.order().get_bin_size());
  cmem_t internal = coinbase::ffi::copy_to_cmem(x_buf);
  return cbmpc_cmem_t{internal.data, internal.size};
}

int cbmpc_eckey_mp_serialize(cbmpc_eckey_mp_t* key, cbmpc_cmems_t* out) {
  if (!key || !key->opaque || !out) return -1;
  eckey::key_share_mp_t* k = static_cast<eckey::key_share_mp_t*>(key->opaque);

  auto x = coinbase::ser(k->x_share);
  auto Q = coinbase::ser(k->Q);
  auto Qis = coinbase::ser(k->Qis);
  auto curve = coinbase::ser(k->curve);
  auto party_name = coinbase::ser(k->party_name);

  auto fields = std::vector<mem_t>{x, Q, Qis, curve, party_name};
  cmems_t internal = coinbase::ffi::copy_to_cmems(fields);
  out->count = internal.count;
  out->data = internal.data;
  out->sizes = internal.sizes;
  return 0;
}

int cbmpc_eckey_mp_deserialize(cbmpc_cmems_t data, cbmpc_eckey_mp_t* out) {
  if (!out) return -1;
  cmems_t internal{data.count, static_cast<uint8_t*>(data.data), data.sizes};
  std::unique_ptr<eckey::key_share_mp_t> key(new eckey::key_share_mp_t());
  std::vector<buf_t> fields = coinbase::ffi::bufs_from_cmems(internal);
  if (fields.size() < 5) return -1;

  if (coinbase::deser(fields[0], key->x_share)) return 1;
  if (coinbase::deser(fields[1], key->Q)) return 1;
  if (coinbase::deser(fields[2], key->Qis)) return 1;
  if (coinbase::deser(fields[3], key->curve)) return 1;
  if (coinbase::deser(fields[4], key->party_name)) return 1;

  out->opaque = key.release();
  return 0;
}

/* Threshold DKG */
int cbmpc_eckey_mp_threshold_dkg(cbmpc_jobmp_t* job, cbmpc_curve_t* curve_ref,
                                  cbmpc_cmem_t sid_mem, cbmpc_ac_t* ac,
                                  cbmpc_party_set_t* quorum, cbmpc_eckey_mp_t* out) {
  if (!job || !job->opaque || !curve_ref || !curve_ref->opaque || !ac || !ac->opaque || !quorum || !quorum->opaque || !out)
    return -1;

  job_mp_t* j = static_cast<job_mp_t*>(job->opaque);
  ecurve_t* curve = static_cast<ecurve_t*>(curve_ref->opaque);
  crypto::ss::ac_t* ac_obj = static_cast<crypto::ss::ac_t*>(ac->opaque);
  party_set_t* quorum_set = static_cast<party_set_t*>(quorum->opaque);

  mem_t sid_raw{static_cast<const uint8_t*>(sid_mem.data), sid_mem.size};
  buf_t sid(sid_raw);

  std::unique_ptr<eckey::key_share_mp_t> key(new eckey::key_share_mp_t());
  error_t err = eckey::key_share_mp_t::threshold_dkg(*j, *curve, sid, *ac_obj, *quorum_set, *key);
  if (err) return err;

  out->opaque = key.release();
  return 0;
}

/* Convert threshold share to additive share */
int cbmpc_eckey_mp_to_additive(cbmpc_eckey_mp_t* key, cbmpc_ac_t* ac,
                                cbmpc_cmems_t quorum_names, cbmpc_eckey_mp_t* out) {
  if (!key || !key->opaque || !ac || !ac->opaque || !out) return -1;

  eckey::key_share_mp_t* k = static_cast<eckey::key_share_mp_t*>(key->opaque);
  crypto::ss::ac_t* ac_obj = static_cast<crypto::ss::ac_t*>(ac->opaque);

  cmems_t internal{quorum_names.count, static_cast<uint8_t*>(quorum_names.data), quorum_names.sizes};
  std::vector<buf_t> name_bufs = coinbase::ffi::bufs_from_cmems(internal);
  std::set<crypto::pname_t> names;
  for (const auto& buf : name_bufs) names.insert(buf.to_string());

  std::unique_ptr<eckey::key_share_mp_t> additive(new eckey::key_share_mp_t());
  error_t err = k->to_additive_share(*ac_obj, names, *additive);
  if (err) return err;

  out->opaque = additive.release();
  return 0;
}

/* Party set operations */
cbmpc_party_set_t* cbmpc_party_set_new(void) {
  auto set = new cbmpc_party_set_t();
  set->opaque = new party_set_t();
  return set;
}

void cbmpc_party_set_add(cbmpc_party_set_t* set, int party_idx) {
  if (!set || !set->opaque) return;
  static_cast<party_set_t*>(set->opaque)->add(party_idx);
}

void cbmpc_party_set_free(cbmpc_party_set_t* set) {
  if (!set) return;
  if (set->opaque) delete static_cast<party_set_t*>(set->opaque);
  delete set;
}

}  // extern "C"
