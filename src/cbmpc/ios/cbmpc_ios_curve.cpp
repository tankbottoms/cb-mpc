#include "cbmpc_ios.h"

#include <memory>

#include <cbmpc/core/buf.h>
#include <cbmpc/crypto/base.h>
#include <cbmpc/ffi/cmem_adapter.h>

using namespace coinbase;
using namespace coinbase::crypto;

extern "C" {

cbmpc_curve_t* cbmpc_curve_new(int curve_code) {
  try {
    ecurve_t* curve = new ecurve_t(ecurve_t::find(curve_code));
    if (!(*curve)) { delete curve; return nullptr; }
    auto result = new cbmpc_curve_t();
    result->opaque = curve;
    return result;
  } catch (...) {
    return nullptr;
  }
}

void cbmpc_curve_free(cbmpc_curve_t* curve) {
  if (!curve) return;
  if (curve->opaque) delete static_cast<ecurve_t*>(curve->opaque);
  delete curve;
}

cbmpc_point_t* cbmpc_point_from_bytes(cbmpc_cmem_t data) {
  try {
    ecc_point_t* point = new ecc_point_t();
    mem_t mem{static_cast<const uint8_t*>(data.data), data.size};
    error_t err = coinbase::deser(mem, *point);
    if (err) { delete point; return nullptr; }
    auto result = new cbmpc_point_t();
    result->opaque = point;
    return result;
  } catch (...) {
    return nullptr;
  }
}

cbmpc_cmem_t cbmpc_point_to_bytes(cbmpc_point_t* point) {
  if (!point || !point->opaque) return cbmpc_cmem_t{nullptr, 0};
  ecc_point_t* p = static_cast<ecc_point_t*>(point->opaque);
  buf_t buf = coinbase::ser(*p);
  cmem_t internal = coinbase::ffi::copy_to_cmem(buf);
  return cbmpc_cmem_t{internal.data, internal.size};
}

void cbmpc_point_free(cbmpc_point_t* point) {
  if (!point) return;
  if (point->opaque) delete static_cast<ecc_point_t*>(point->opaque);
  delete point;
}

cbmpc_cmem_t cbmpc_point_get_x(cbmpc_point_t* point) {
  if (!point || !point->opaque) return cbmpc_cmem_t{nullptr, 0};
  ecc_point_t* p = static_cast<ecc_point_t*>(point->opaque);
  buf_t x = p->get_x().to_bin();
  cmem_t internal = coinbase::ffi::copy_to_cmem(x);
  return cbmpc_cmem_t{internal.data, internal.size};
}

cbmpc_cmem_t cbmpc_point_get_y(cbmpc_point_t* point) {
  if (!point || !point->opaque) return cbmpc_cmem_t{nullptr, 0};
  ecc_point_t* p = static_cast<ecc_point_t*>(point->opaque);
  buf_t y = p->get_y().to_bin();
  cmem_t internal = coinbase::ffi::copy_to_cmem(y);
  return cbmpc_cmem_t{internal.data, internal.size};
}

}  // extern "C"
