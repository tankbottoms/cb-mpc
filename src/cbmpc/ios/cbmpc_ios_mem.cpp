#include "cbmpc_ios.h"
#include <cbmpc/ffi/cmem_adapter.h>

/* Re-export cgo_malloc and cgo_free as cbmpc_malloc and cbmpc_free
 * These are defined in src/cbmpc/ffi/cmem_adapter.h and implemented
 * in src/cbmpc/ffi/cmem_adapter.cpp
 */

extern "C" {

void* cbmpc_malloc(int size) {
  return cgo_malloc(size);
}

void cbmpc_free(void* ptr) {
  cgo_free(ptr);
}

}  // extern "C"
