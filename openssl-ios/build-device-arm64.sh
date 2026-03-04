#!/usr/bin/env bash

# Build OpenSSL 3.2.0 for iOS device (arm64)
# This is necessary for real device deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSSL_VERSION="3.2.0"
OPENSSL_SOURCE="${SCRIPT_DIR}/../openssl-${OPENSSL_VERSION}"
OUTPUT_DIR="${SCRIPT_DIR}/ios-arm64"

echo "🔨 Building OpenSSL $OPENSSL_VERSION for iOS device (arm64)"
echo "=================================================="
echo ""

# Check if source exists
if [ ! -d "$OPENSSL_SOURCE" ]; then
    echo "⚠️  OpenSSL source not found at $OPENSSL_SOURCE"
    echo ""
    echo "Downloading OpenSSL $OPENSSL_VERSION..."
    cd "${SCRIPT_DIR}/.."
    curl -sL "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" -o "openssl-${OPENSSL_VERSION}.tar.gz"
    tar -xzf "openssl-${OPENSSL_VERSION}.tar.gz"
    echo "✓ Downloaded and extracted"
    echo ""
fi

# Create output directories
mkdir -p "${OUTPUT_DIR}/lib"
mkdir -p "${OUTPUT_DIR}/include"

echo "Step 1: Configuring OpenSSL for iOS device (arm64)..."
echo ""

cd "$OPENSSL_SOURCE"

# Configure for iOS device (ios64-xcrun for actual device ARM64, not simulator)
echo "Configure command:"
echo "  ./Configure ios64-xcrun no-shared no-tests no-docs \\"
echo "    --openssldir=${OUTPUT_DIR}"
echo ""

./Configure ios64-xcrun no-shared no-tests no-docs \
  --openssldir="${OUTPUT_DIR}" \
  2>&1 | tail -20

echo ""
echo "✓ Configuration complete"
echo ""

echo "Step 2: Building OpenSSL..."
echo ""

# Build
make -j$(sysctl -n hw.ncpu) 2>&1 | tail -10

echo ""
echo "✓ Build complete"
echo ""

echo "Step 3: Installing to ${OUTPUT_DIR}..."
echo ""

# Install
make install_sw DESTDIR="${OUTPUT_DIR}" 2>&1 | tail -5

echo ""
echo "✓ Installation complete"
echo ""

# Copy libraries to the right place
echo "Step 4: Organizing libraries..."
if [ -d "${OUTPUT_DIR}/usr/local/lib" ]; then
    cp "${OUTPUT_DIR}/usr/local/lib/"*.a "${OUTPUT_DIR}/lib/" 2>/dev/null || true
fi
if [ -d "${OUTPUT_DIR}/usr/local/include" ]; then
    cp -r "${OUTPUT_DIR}/usr/local/include/"* "${OUTPUT_DIR}/include/" 2>/dev/null || true
fi

echo "✓ Libraries organized"
echo ""

# Verify
echo "Step 5: Verifying libraries..."
if [ -f "${OUTPUT_DIR}/lib/libssl.a" ] && [ -f "${OUTPUT_DIR}/lib/libcrypto.a" ]; then
    echo "✓ libssl.a: $(ls -lh ${OUTPUT_DIR}/lib/libssl.a | awk '{print $5}')"
    echo "✓ libcrypto.a: $(ls -lh ${OUTPUT_DIR}/lib/libcrypto.a | awk '{print $5}')"
    echo ""
    echo "✓ Headers available:"
    ls -1 "${OUTPUT_DIR}/include/openssl" | head -10
    echo "  ... (and more)"
    echo ""
else
    echo "❌ Libraries not found in ${OUTPUT_DIR}/lib/"
    exit 1
fi

echo "=================================================="
echo "✓ OpenSSL build complete for iOS device!"
echo ""
echo "Locations:"
echo "  Libraries: ${OUTPUT_DIR}/lib/"
echo "  Headers:   ${OUTPUT_DIR}/include/"
echo ""
echo "Next: Update Xcode project to use these libraries"
echo ""
