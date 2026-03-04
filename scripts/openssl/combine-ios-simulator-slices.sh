#!/bin/bash
set -e

# Combine iOS Simulator arm64 and x86_64 slices into a fat binary
# Usage: ./combine-ios-simulator-slices.sh [openssl_root_path]

OPENSSL_ROOT="${1:-.}"

if [ ! -d "$OPENSSL_ROOT/openssl-ios/iossimulator-arm64/lib" ]; then
  echo "ERROR: arm64 slice not found at $OPENSSL_ROOT/openssl-ios/iossimulator-arm64/lib"
  exit 1
fi

if [ ! -d "$OPENSSL_ROOT/openssl-ios/iossimulator-x86_64/lib" ]; then
  echo "ERROR: x86_64 slice not found at $OPENSSL_ROOT/openssl-ios/iossimulator-x86_64/lib"
  exit 1
fi

mkdir -p "$OPENSSL_ROOT/openssl-ios/iossimulator/lib"

echo "Creating fat binary: libcrypto.a"
lipo -create \
  "$OPENSSL_ROOT/openssl-ios/iossimulator-arm64/lib/libcrypto.a" \
  "$OPENSSL_ROOT/openssl-ios/iossimulator-x86_64/lib/libcrypto.a" \
  -output "$OPENSSL_ROOT/openssl-ios/iossimulator/lib/libcrypto.a"

# Copy include directory from one of the slices (they're identical)
mkdir -p "$OPENSSL_ROOT/openssl-ios/iossimulator/include"
cp -r "$OPENSSL_ROOT/openssl-ios/iossimulator-arm64/include/openssl" "$OPENSSL_ROOT/openssl-ios/iossimulator/include/"

echo "Done. Combined simulator library at: $OPENSSL_ROOT/openssl-ios/iossimulator/lib/libcrypto.a"
