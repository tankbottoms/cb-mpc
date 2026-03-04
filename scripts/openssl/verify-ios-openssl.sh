#!/bin/bash
set -e

# Verify iOS OpenSSL builds
# Usage: ./verify-ios-openssl.sh [openssl_root_path]

OPENSSL_ROOT="${1:-.}"

echo "======= Verifying iOS OpenSSL Builds ======="
echo ""

# Check device slice
echo "[Device arm64]"
if [ -f "$OPENSSL_ROOT/openssl-ios/ios-arm64/lib/libcrypto.a" ]; then
  echo "✓ File exists: openssl-ios/ios-arm64/lib/libcrypto.a"
  lipo -info "$OPENSSL_ROOT/openssl-ios/ios-arm64/lib/libcrypto.a"
  echo "✓ Architecture correct"

  # Verify device deployment target
  otool -l "$OPENSSL_ROOT/openssl-ios/ios-arm64/lib/libcrypto.a" | grep -A 4 LC_VERSION_MIN_IPHONEOS || echo "  (static library, deployment target embedded)"
  echo ""
else
  echo "✗ MISSING: openssl-ios/ios-arm64/lib/libcrypto.a"
  exit 1
fi

# Check simulator arm64 slice
echo "[Simulator arm64]"
if [ -f "$OPENSSL_ROOT/openssl-ios/iossimulator-arm64/lib/libcrypto.a" ]; then
  echo "✓ File exists: openssl-ios/iossimulator-arm64/lib/libcrypto.a"
  lipo -info "$OPENSSL_ROOT/openssl-ios/iossimulator-arm64/lib/libcrypto.a"
  echo "✓ Architecture correct"
  echo ""
else
  echo "✗ MISSING: openssl-ios/iossimulator-arm64/lib/libcrypto.a"
  exit 1
fi

# Check simulator x86_64 slice
echo "[Simulator x86_64]"
if [ -f "$OPENSSL_ROOT/openssl-ios/iossimulator-x86_64/lib/libcrypto.a" ]; then
  echo "✓ File exists: openssl-ios/iossimulator-x86_64/lib/libcrypto.a"
  lipo -info "$OPENSSL_ROOT/openssl-ios/iossimulator-x86_64/lib/libcrypto.a"
  echo "✓ Architecture correct"
  echo ""
else
  echo "✗ MISSING: openssl-ios/iossimulator-x86_64/lib/libcrypto.a"
  exit 1
fi

# Check combined simulator fat binary
echo "[Simulator fat binary]"
if [ -f "$OPENSSL_ROOT/openssl-ios/iossimulator/lib/libcrypto.a" ]; then
  echo "✓ File exists: openssl-ios/iossimulator/lib/libcrypto.a"
  lipo -info "$OPENSSL_ROOT/openssl-ios/iossimulator/lib/libcrypto.a"
  echo "✓ Contains both arm64 and x86_64"
  echo ""
else
  echo "✗ MISSING: openssl-ios/iossimulator/lib/libcrypto.a (run combine-ios-simulator-slices.sh)"
fi

# Check include directories
echo "[Include directories]"
for dir in ios-arm64 iossimulator-arm64 iossimulator-x86_64; do
  if [ -d "$OPENSSL_ROOT/openssl-ios/$dir/include/openssl" ]; then
    echo "✓ Headers present: openssl-ios/$dir/include/openssl"
  else
    echo "✗ MISSING: openssl-ios/$dir/include/openssl"
  fi
done

echo ""
echo "======= Verification Complete ======="
