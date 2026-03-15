if(NOT IS_IOS AND NOT IS_IOS_SIMULATOR AND NOT IS_MACOS)
  return()  # Skip API layer if not building for iOS or macOS
endif()

add_library(cbmpc_ios OBJECT
  cbmpc_ios_mem.cpp
  cbmpc_ios_network.cpp
  cbmpc_ios_ecdsa2p.cpp
  cbmpc_ios_hd.cpp
  cbmpc_ios_agree_random.cpp
  cbmpc_ios_zk.cpp
  cbmpc_ios_jobmp.cpp
  cbmpc_ios_curve.cpp
  cbmpc_ios_eckeymp.cpp
  cbmpc_ios_ecdsamp.cpp
  cbmpc_ios_eddsamp.cpp
  cbmpc_ios_ac.cpp
)

target_include_directories(cbmpc_ios PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_precompile_headers(cbmpc_ios REUSE_FROM cbmpc_core)

link_openssl(cbmpc_ios)
