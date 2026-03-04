#!/usr/bin/env bash

# Device Deployment Setup for CBMPCNative
# Team ID: YT6VJY3L35
# Device Serial: DM2CX6RY25

set -e

TEAM_ID="YT6VJY3L35"
BUNDLE_ID="com.coinbase.cbmpc.demo"
PROJECT_DIR="/Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1/CBMPCNative"
XCODEPROJ="${PROJECT_DIR}/CBMPCNative.xcodeproj"

echo "🚀 CBMPCNative Device Deployment Setup"
echo "========================================"
echo "Team ID: $TEAM_ID"
echo "Bundle ID: $BUNDLE_ID"
echo ""

# Step 1: Check if device is connected
echo "Step 1: Checking for connected iOS devices..."
DEVICES=$(xcrun xctrace list devices 2>/dev/null | grep -v "Simulator")
if [ -z "$DEVICES" ]; then
    echo "⚠️  No physical iOS devices detected"
    echo "   Plug in your iPhone (Serial: DM2CX6RY25) and trust it"
    echo ""
    exit 1
fi
echo "✓ Found iOS devices:"
echo "$DEVICES"
echo ""

# Step 2: Find device UUID
echo "Step 2: Finding device UUID..."
DEVICE_UUID=$(xcrun xctrace list devices 2>/dev/null | grep -v "Simulator" | head -1 | grep -oE '\([A-F0-9\-]+\)' | tr -d '()')
if [ -z "$DEVICE_UUID" ]; then
    echo "❌ Could not find device UUID"
    echo "   Make sure your iPhone is connected and trusted"
    exit 1
fi
echo "✓ Device UUID: $DEVICE_UUID"
echo ""

# Step 3: Build OpenSSL for device (ios-arm64)
echo "Step 3: Building OpenSSL for device (ios-arm64)..."
echo "   Command to run manually:"
echo "   cd ${PROJECT_DIR} && ./openssl-ios/build-device.sh"
echo ""
echo "   Or build the libraries you need:"
OPENSSL_DEVICE_LIB="${PROJECT_DIR}/openssl-ios/ios-arm64/lib"
if [ -f "${OPENSSL_DEVICE_LIB}/libssl.a" ] && [ -f "${OPENSSL_DEVICE_LIB}/libcrypto.a" ]; then
    echo "✓ OpenSSL device libraries found at:"
    echo "  - ${OPENSSL_DEVICE_LIB}/libssl.a"
    echo "  - ${OPENSSL_DEVICE_LIB}/libcrypto.a"
else
    echo "⚠️  OpenSSL device libraries not found"
    echo "   You need to build OpenSSL for ios-arm64:"
    echo ""
    echo "   Manual build commands:"
    echo "   cd ${PROJECT_DIR}/openssl-3.2.0"
    echo "   ./Configure ios64 no-shared"
    echo "   make"
    echo "   make install DESTDIR=${PROJECT_DIR}/openssl-ios/ios-arm64"
    echo ""
fi
echo ""

# Step 4: Update Xcode project for device
echo "Step 4: Updating Xcode project for device signing..."
echo "   Setting DEVELOPMENT_TEAM to $TEAM_ID"
echo ""

# Update pbxproj with team ID
if ! grep -q "DEVELOPMENT_TEAM = $TEAM_ID" "$XCODEPROJ/project.pbxproj"; then
    echo "   Adding team ID to project settings..."
    sed -i '' "s/DEVELOPMENT_TEAM = ;/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$XCODEPROJ/project.pbxproj" || true
fi

echo "   ✓ Project updated"
echo ""

# Step 5: Show build commands
echo "Step 5: Building for device..."
echo ""
echo "Run these commands in sequence:"
echo ""
echo "# Build for device:"
echo "xcodebuild build -scheme CBMPCNative \\"
echo "  -project ${XCODEPROJ} \\"
echo "  -destination 'generic/platform=iOS' \\"
echo "  -configuration Release"
echo ""
echo "# Or build and archive:"
echo "xcodebuild archive -scheme CBMPCNative \\"
echo "  -project ${XCODEPROJ} \\"
echo "  -archivePath ./CBMPCNative.xcarchive \\"
echo "  -configuration Release"
echo ""

# Step 6: Show installation commands
echo "Step 6: Installing on device..."
echo ""
echo "Once built, install using:"
echo ""
echo "# Option 1: Via Xcode"
echo "xcodebuild install -scheme CBMPCNative \\"
echo "  -project ${XCODEPROJ} \\"
echo "  -destination 'id=${DEVICE_UUID}' \\"
echo "  -configuration Release"
echo ""
echo "# Option 2: Via simctl (for development)"
echo "xcrun xcodebuild install -scheme CBMPCNative \\"
echo "  -project ${XCODEPROJ} \\"
echo "  -destination 'id=${DEVICE_UUID}'"
echo ""

# Step 7: Show signing setup
echo "Step 7: Automatic Code Signing..."
echo ""
echo "Xcode will automatically sign your app with Team ID: $TEAM_ID"
echo ""
echo "If you encounter signing issues:"
echo "1. Open ${XCODEPROJ} in Xcode"
echo "2. Select the CBMPCNative target"
echo "3. Go to Signing & Capabilities"
echo "4. Ensure Team is set to '$TEAM_ID'"
echo "5. Xcode will handle certificate selection automatically"
echo ""

echo "========================================"
echo "✓ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Connect your iPhone (DM2CX6RY25)"
echo "2. Trust the device in Xcode"
echo "3. Run the build commands above"
echo ""
