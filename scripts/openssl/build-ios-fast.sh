#!/bin/bash
set -e

# Fast OpenSSL 3.2.0 build for iOS - just the crypto library
# Usage: ./build-ios-fast.sh /path/to/openssl-source [output-dir]

OPENSSL_SRC="${1:-.}"
OUTPUT_DIR="${2:-.}"

if [ ! -f "$OPENSSL_SRC/Configure" ]; then
  echo "ERROR: OpenSSL source not found at $OPENSSL_SRC/Configure"
  exit 1
fi

echo "Fast OpenSSL build from: $OPENSSL_SRC"
mkdir -p "$OUTPUT_DIR/openssl-ios"

# Prepare source
TEMP_SRC="/tmp/openssl-ios-build-$$"
cp -r "$OPENSSL_SRC" "$TEMP_SRC"
cd "$TEMP_SRC"
sed -i -e 's/^static //' crypto/ec/curve25519.c

# iOS arm64 (device)
echo "Building iOS arm64..."
./Configure ios64-xcrun \
  -g3 -static -DOPENSSL_THREADS no-shared no-tests no-apps no-docs \
  no-afalgeng no-aria no-bf no-camellia no-cast no-chacha no-cms \
  no-comp no-ct no-des no-dh no-dgram no-dsa no-dso no-dtls \
  no-ec2m no-egd no-engine no-gost no-http no-idea no-mdc2 no-md2 no-md4 \
  no-module no-nextprotoneg no-ocb no-ocsp no-psk no-padlockeng no-poly1305 \
  no-quic no-rc2 no-rc4 no-rc5 no-rfc3779 no-scrypt no-sctp no-seed \
  no-siphash no-sm2 no-sm3 no-sm4 no-sock no-srtp no-srp no-ssl-trace no-ssl3 \
  no-stdio no-tls no-ts no-unit-test no-uplink no-whirlpool no-zlib \
  --prefix="$OUTPUT_DIR/openssl-ios/ios-arm64" &>/dev/null

make build_libs -j$(sysctl -n hw.ncpu) &>/dev/null
make install_sw &>/dev/null
make clean &>/dev/null

# iOS Simulator arm64
echo "Building iOS Simulator arm64..."
./Configure iossimulator-xcrun \
  -g3 -static -DOPENSSL_THREADS no-shared no-tests no-apps no-docs \
  no-afalgeng no-aria no-bf no-camellia no-cast no-chacha no-cms \
  no-comp no-ct no-des no-dh no-dgram no-dsa no-dso no-dtls \
  no-ec2m no-egd no-engine no-gost no-http no-idea no-mdc2 no-md2 no-md4 \
  no-module no-nextprotoneg no-ocb no-ocsp no-psk no-padlockeng no-poly1305 \
  no-quic no-rc2 no-rc4 no-rc5 no-rfc3779 no-scrypt no-sctp no-seed \
  no-siphash no-sm2 no-sm3 no-sm4 no-sock no-srtp no-srp no-ssl-trace no-ssl3 \
  no-stdio no-tls no-ts no-unit-test no-uplink no-whirlpool no-zlib \
  --prefix="$OUTPUT_DIR/openssl-ios/iossimulator-arm64" &>/dev/null

make build_libs -j$(sysctl -n hw.ncpu) &>/dev/null
make install_sw &>/dev/null
make clean &>/dev/null

# iOS Simulator x86_64
echo "Building iOS Simulator x86_64..."
./Configure iossimulator-xcrun \
  -g3 -static -DOPENSSL_THREADS no-shared no-tests no-apps no-docs \
  no-afalgeng no-aria no-bf no-camellia no-cast no-chacha no-cms \
  no-comp no-ct no-des no-dh no-dgram no-dsa no-dso no-dtls \
  no-ec2m no-egd no-engine no-gost no-http no-idea no-mdc2 no-md2 no-md4 \
  no-module no-nextprotoneg no-ocb no-ocsp no-psk no-padlockeng no-poly1305 \
  no-quic no-rc2 no-rc4 no-rc5 no-rfc3779 no-scrypt no-sctp no-seed \
  no-siphash no-sm2 no-sm3 no-sm4 no-sock no-srtp no-srp no-ssl-trace no-ssl3 \
  no-stdio no-tls no-ts no-unit-test no-uplink no-whirlpool no-zlib \
  --prefix="$OUTPUT_DIR/openssl-ios/iossimulator-x86_64" &>/dev/null

make build_libs -j$(sysctl -n hw.ncpu) &>/dev/null
make install_sw &>/dev/null

# Create fat simulator binary
echo "Creating fat simulator binary..."
mkdir -p "$OUTPUT_DIR/openssl-ios/iossimulator/lib"
mkdir -p "$OUTPUT_DIR/openssl-ios/iossimulator/include"
lipo -create \
  "$OUTPUT_DIR/openssl-ios/iossimulator-arm64/lib/libcrypto.a" \
  "$OUTPUT_DIR/openssl-ios/iossimulator-x86_64/lib/libcrypto.a" \
  -output "$OUTPUT_DIR/openssl-ios/iossimulator/lib/libcrypto.a" 2>/dev/null
cp -r "$OUTPUT_DIR/openssl-ios/iossimulator-arm64/include/openssl" \
  "$OUTPUT_DIR/openssl-ios/iossimulator/include/" 2>/dev/null || true

echo ""
echo "✓ OpenSSL build complete!"
ls -lh "$OUTPUT_DIR/openssl-ios/ios-arm64/lib/libcrypto.a" 2>/dev/null
ls -lh "$OUTPUT_DIR/openssl-ios/iossimulator/lib/libcrypto.a" 2>/dev/null

rm -rf "$TEMP_SRC"
