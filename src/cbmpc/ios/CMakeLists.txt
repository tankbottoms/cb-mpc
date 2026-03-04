if(NOT IS_IOS AND NOT IS_IOS_SIMULATOR)
  return()  # Skip iOS API layer if not building for iOS
endif()

add_library(cbmpc_ios OBJECT
  cbmpc_ios_mem.cpp
  cbmpc_ios_network.cpp
  cbmpc_ios_ecdsa2p.cpp
  cbmpc_ios_hd.cpp
)

target_include_directories(cbmpc_ios PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_precompile_headers(cbmpc_ios REUSE_FROM cbmpc_core)

link_openssl(cbmpc_ios)
