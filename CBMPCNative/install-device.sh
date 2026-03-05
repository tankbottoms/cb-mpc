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
