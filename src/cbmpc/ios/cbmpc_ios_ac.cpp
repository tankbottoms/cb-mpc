#include "cbmpc_ios.h"

#include <cbmpc/core/buf.h>
#include <cbmpc/crypto/base.h>
#include <cbmpc/crypto/secret_sharing.h>
#include <cbmpc/ffi/cmem_adapter.h>

using namespace coinbase;
using namespace coinbase::crypto;
using node_t = coinbase::crypto::ss::node_t;
using node_e = coinbase::crypto::ss::node_e;

extern "C" {

cbmpc_ac_node_t* cbmpc_ac_node_new(int node_type, const char* name, int threshold) {
  if (!name) return nullptr;
  try {
    node_t* node = new node_t(node_e(node_type), std::string(name), threshold);
    auto result = new cbmpc_ac_node_t();
    result->opaque = node;
    return result;
  } catch (...) {
    return nullptr;
  }
}

void cbmpc_ac_node_add_child(cbmpc_ac_node_t* parent, cbmpc_ac_node_t* child) {
  if (!parent || !parent->opaque || !child || !child->opaque) return;
  node_t* p = static_cast<node_t*>(parent->opaque);
  node_t* c = static_cast<node_t*>(child->opaque);
  p->add_child_node(c);
}

cbmpc_ac_t* cbmpc_ac_new(cbmpc_ac_node_t* root, cbmpc_curve_t* curve_ref) {
  if (!root || !root->opaque) return nullptr;
  try {
    node_t* root_node = static_cast<node_t*>(root->opaque);
    crypto::ss::ac_t* ac = new crypto::ss::ac_t();

    if (curve_ref && curve_ref->opaque) {
      ecurve_t* curve = static_cast<ecurve_t*>(curve_ref->opaque);
      ac->G = curve->generator();
    }
    ac->root = root_node;

    auto result = new cbmpc_ac_t();
    result->opaque = ac;
    return result;
  } catch (...) {
    return nullptr;
  }
}

void cbmpc_ac_free(cbmpc_ac_t* ac) {
  if (!ac) return;
  if (ac->opaque) {
    delete static_cast<crypto::ss::ac_t*>(ac->opaque);
  }
  delete ac;
}

}  // extern "C"
