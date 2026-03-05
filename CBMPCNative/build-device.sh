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
  -allowProvisioningUpdates \
  archive

echo ""
echo "✓ Build complete!"
echo ""
echo "Archive location: ./CBMPCNative-device.xcarchive"
echo ""
