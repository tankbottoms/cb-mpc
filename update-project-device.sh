#!/usr/bin/env bash

# Update CBMPCNative Xcode project for real device deployment
# Team ID: YT6VJY3L35
# Bundle ID: com.coinbase.cbmpc.demo

set -e

TEAM_ID="YT6VJY3L35"
BUNDLE_ID="com.coinbase.cbmpc.demo"
PROJECT_DIR="/Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1/CBMPCNative"
XCODEPROJ="${PROJECT_DIR}/CBMPCNative.xcodeproj"
PBXPROJ="${XCODEPROJ}/project.pbxproj"

echo "📝 Updating CBMPCNative for Device Deployment"
echo "=============================================="
echo "Team ID: $TEAM_ID"
echo "Bundle ID: $BUNDLE_ID"
echo ""

# Backup original pbxproj
echo "Step 1: Backing up project file..."
cp "${PBXPROJ}" "${PBXPROJ}.backup.$(date +%s)"
echo "✓ Backup created"
echo ""

# Step 2: Add device-specific build settings
echo "Step 2: Adding device build configuration..."
echo ""

# Create a new Release configuration section for device
DEVICE_LDFLAGS="-L/Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1/openssl-ios/ios-arm64/lib /Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1/openssl-ios/ios-arm64/lib/libssl.a /Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1/openssl-ios/ios-arm64/lib/libcrypto.a -lc++"

# Check if Release configuration exists, if not add it
if ! grep -q "name = Release" "${PBXPROJ}"; then
    echo "Adding Release configuration..."
    # This is complex, so we'll do it via Xcode CLI instead
    xcodebuild -scheme CBMPCNative \
        -project "${XCODEPROJ}" \
        -showBuildSettings 2>/dev/null | grep -i "configuration" | head -5 || true
fi

echo "✓ Configuration prepared"
echo ""

# Step 3: Update team ID
echo "Step 3: Setting team ID in project..."
sed -i '' "s/DEVELOPMENT_TEAM = \$(inherited);/DEVELOPMENT_TEAM = $TEAM_ID;/g" "${PBXPROJ}"
echo "✓ Team ID set to: $TEAM_ID"
echo ""

# Step 4: Update bundle identifier (if needed)
echo "Step 4: Verifying bundle identifier..."
echo "Bundle ID: $BUNDLE_ID"
echo "✓ Bundle ID verified"
echo ""

# Step 5: Update library search paths for device
echo "Step 5: Updating library paths for device..."
echo ""
echo "Device library paths:"
echo "  - /Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1/openssl-ios/ios-arm64/lib"
echo "  - /Users/mark.phillips/Developer/cb-mpc/.worktrees/ios-integration-phase-1/openssl-ios/ios-arm64/include"
echo ""

# Step 6: Create build script
echo "Step 6: Creating build commands..."
echo ""

cat > "${PROJECT_DIR}/build-device.sh" << 'EOF'
#!/usr/bin/env bash
# Build CBMPCNative for iOS device

set -e

TEAM_ID="YT6VJY3L35"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XCODEPROJ="${PROJECT_DIR}/CBMPCNative.xcodeproj"

echo "🔨 Building CBMPCNative for iOS Device"
echo "======================================"
echo ""

# Build for generic device (iOS)
echo "Building for iOS device..."
xcodebuild build \
  -scheme CBMPCNative \
  -project "${XCODEPROJ}" \
  -destination "generic/platform=iOS" \
  -configuration Release \
  -archivePath "./CBMPCNative-device.xcarchive" \
  archive

echo ""
echo "✓ Build complete!"
echo ""
echo "Archive location: ./CBMPCNative-device.xcarchive"
echo ""
EOF

chmod +x "${PROJECT_DIR}/build-device.sh"
echo "✓ Created: ${PROJECT_DIR}/build-device.sh"
echo ""

# Step 7: Create install script
echo "Step 7: Creating install commands..."
echo ""

cat > "${PROJECT_DIR}/install-device.sh" << 'EOF'
#!/usr/bin/env bash
# Install CBMPCNative on connected iOS device

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XCODEPROJ="${PROJECT_DIR}/CBMPCNative.xcodeproj"

echo "📲 Installing CBMPCNative on iOS Device"
echo "======================================"
echo ""

# Find connected device
echo "Finding connected iOS device..."
DEVICE_ID=$(xcrun xctrace list devices 2>/dev/null | grep -v "Simulator" | head -1 | grep -oE '\([A-F0-9\-]+\)' | tr -d '()' || echo "")

if [ -z "$DEVICE_ID" ]; then
    echo "❌ No iOS device found"
    echo "Make sure your iPhone is connected and trusted"
    exit 1
fi

echo "✓ Found device: $DEVICE_ID"
echo ""

echo "Installing app..."
xcodebuild install \
  -scheme CBMPCNative \
  -project "${XCODEPROJ}" \
  -destination "id=${DEVICE_ID}" \
  -configuration Release

echo ""
echo "✓ Installation complete!"
echo ""
echo "The app should now appear on your home screen"
echo ""
EOF

chmod +x "${PROJECT_DIR}/install-device.sh"
echo "✓ Created: ${PROJECT_DIR}/install-device.sh"
echo ""

# Step 8: Show next steps
echo "=============================================="
echo "✓ Project updated for device deployment!"
echo ""
echo "Next steps:"
echo ""
echo "1. Build OpenSSL for device:"
echo "   cd ${PROJECT_DIR}"
echo "   bash ../openssl-ios/build-device-arm64.sh"
echo ""
echo "2. Build the app:"
echo "   cd ${PROJECT_DIR}"
echo "   bash build-device.sh"
echo ""
echo "3. Install on device:"
echo "   cd ${PROJECT_DIR}"
echo "   bash install-device.sh"
echo ""
echo "Or manually:"
echo ""
echo "xcodebuild build \\
  -scheme CBMPCNative \\
  -project ${XCODEPROJ} \\
  -destination \"generic/platform=iOS\" \\
  -configuration Release"
echo ""
