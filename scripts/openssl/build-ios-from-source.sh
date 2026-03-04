#!/bin/bash
set -e

# Build OpenSSL 3.2.0 for iOS from existing source
# Usage: ./build-ios-from-source.sh /path/to/openssl-source [output-dir]

OPENSSL_SRC="${1:-.}"
OUTPUT_DIR="${2:-.}"

if [ ! -f "$OPENSSL_SRC/Configure" ]; then
  echo "ERROR: OpenSSL source not found at $OPENSSL_SRC/Configure"
  exit 1
fi

echo "Building OpenSSL from: $OPENSSL_SRC"
echo "Output directory: $OUTPUT_DIR"

# Create output directories
mkdir -p "$OUTPUT_DIR/openssl-ios/ios-arm64"
mkdir -p "$OUTPUT_DIR/openssl-ios/iossimulator-arm64"
mkdir -p "$OUTPUT_DIR/openssl-ios/iossimulator-x86_64"

# Copy source to temp and patch
TEMP_SRC="/tmp/openssl-build-$$"
cp -r "$OPENSSL_SRC" "$TEMP_SRC"
cd "$TEMP_SRC"

echo "[1/5] Patching curve25519.c..."
sed -i -e 's/^static //' crypto/ec/curve25519.c

echo "[2/5] Building iOS arm64 (device)..."
iOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
./Configure -g3 -static -DOPENSSL_THREADS no-shared \
  no-afalgeng no-apps no-aria no-autoload-config no-bf no-camellia no-cast no-chacha no-cmac no-cms no-crypto-mdebug \
  no-comp no-cmp no-ct no-des no-dh no-dgram no-dsa no-dso no-dtls no-dynamic-engine no-ec2m no-egd no-engine no-external-tests \
  no-gost no-http no-idea no-mdc2 no-md2 no-md4 no-module no-nextprotoneg no-ocb no-ocsp no-psk no-padlockeng no-poly1305 \
  no-quic no-rc2 no-rc4 no-rc5 no-rfc3779 no-scrypt no-sctp no-seed no-siphash no-sm2 no-sm3 no-sm4 no-sock no-srtp no-srp \
  no-ssl-trace no-ssl3 no-stdio no-tests no-tls no-ts no-unit-test no-uplink no-whirlpool no-zlib \
  --prefix="$OUTPUT_DIR/openssl-ios/ios-arm64" \
  ios64-xcrun > /dev/null 2>&1
make -j$(sysctl -n hw.ncpu) > /dev/null 2>&1
make install_sw > /dev/null 2>&1
make clean > /dev/null 2>&1

echo "[3/5] Building iOS Simulator arm64..."
Sim_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
./Configure -g3 -static -DOPENSSL_THREADS no-shared \
  no-afalgeng no-apps no-aria no-autoload-config no-bf no-camellia no-cast no-chacha no-cmac no-cms no-crypto-mdebug \
  no-comp no-cmp no-ct no-des no-dh no-dgram no-dsa no-dso no-dtls no-dynamic-engine no-ec2m no-egd no-engine no-external-tests \
  no-gost no-http no-idea no-mdc2 no-md2 no-md4 no-module no-nextprotoneg no-ocb no-ocsp no-psk no-padlockeng no-poly1305 \
  no-quic no-rc2 no-rc4 no-rc5 no-rfc3779 no-scrypt no-sctp no-seed no-siphash no-sm2 no-sm3 no-sm4 no-sock no-srtp no-srp \
  no-ssl-trace no-ssl3 no-stdio no-tests no-tls no-ts no-unit-test no-uplink no-whirlpool no-zlib \
  --prefix="$OUTPUT_DIR/openssl-ios/iossimulator-arm64" \
  iossimulator-xcrun > /dev/null 2>&1
make -j$(sysctl -n hw.ncpu) > /dev/null 2>&1
make install_sw > /dev/null 2>&1
make clean > /dev/null 2>&1

echo "[4/5] Building iOS Simulator x86_64..."
./Configure -g3 -static -DOPENSSL_THREADS no-shared \
  no-afalgeng no-apps no-aria no-autoload-config no-bf no-camellia no-cast no-chacha no-cmac no-cms no-crypto-mdebug \
  no-comp no-cmp no-ct no-des no-dh no-dgram no-dsa no-dso no-dtls no-dynamic-engine no-ec2m no-egd no-engine no-external-tests \
  no-gost no-http no-idea no-mdc2 no-md2 no-md4 no-module no-nextprotoneg no-ocb no-ocsp no-psk no-padlockeng no-poly1305 \
  no-quic no-rc2 no-rc4 no-rc5 no-rfc3779 no-scrypt no-sctp no-seed no-siphash no-sm2 no-sm3 no-sm4 no-sock no-srtp no-srp \
  no-ssl-trace no-ssl3 no-stdio no-tests no-tls no-ts no-unit-test no-uplink no-whirlpool no-zlib \
  --prefix="$OUTPUT_DIR/openssl-ios/iossimulator-x86_64" \
  iossimulator-xcrun > /dev/null 2>&1
make -j$(sysctl -n hw.ncpu) > /dev/null 2>&1
make install_sw > /dev/null 2>&1

echo "[5/5] Creating fat simulator binary..."
mkdir -p "$OUTPUT_DIR/openssl-ios/iossimulator/lib"
mkdir -p "$OUTPUT_DIR/openssl-ios/iossimulator/include"
lipo -create \
  "$OUTPUT_DIR/openssl-ios/iossimulator-arm64/lib/libcrypto.a" \
  "$OUTPUT_DIR/openssl-ios/iossimulator-x86_64/lib/libcrypto.a" \
  -output "$OUTPUT_DIR/openssl-ios/iossimulator/lib/libcrypto.a"
cp -r "$OUTPUT_DIR/openssl-ios/iossimulator-arm64/include/openssl" "$OUTPUT_DIR/openssl-ios/iossimulator/include/"

echo ""
echo "✓ OpenSSL build complete!"
echo ""
echo "Device (arm64):       $OUTPUT_DIR/openssl-ios/ios-arm64/lib/libcrypto.a"
echo "Simulator (fat):      $OUTPUT_DIR/openssl-ios/iossimulator/lib/libcrypto.a"
echo ""

# Cleanup
rm -rf "$TEMP_SRC"
