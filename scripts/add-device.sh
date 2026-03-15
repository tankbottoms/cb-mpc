#!/usr/bin/env bash
set -euo pipefail

# Add a connected iOS device to .env.json and display build/install commands.
# Usage: ./scripts/add-device.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_JSON="${PROJECT_DIR}/.env.json"

if [ ! -f "$ENV_JSON" ]; then
  echo "ERROR: .env.json not found at $ENV_JSON"
  echo "Run ./scripts/validate-env.sh first."
  exit 1
fi

echo "Scanning for connected devices..."
echo ""

# Get connected devices (xcrun devicectl is the modern replacement for idevice_id)
DEVICE_LIST=$(xcrun devicectl list devices 2>&1) || {
  echo "ERROR: xcrun devicectl failed. Is Xcode installed?"
  echo "  Install: xcode-select --install"
  exit 1
}

echo "$DEVICE_LIST"
echo ""
echo "---"
echo ""

# Prompt for device details
read -rp "Paste the device UDID from the list above: " UDID
if [ -z "$UDID" ]; then
  echo "ERROR: UDID cannot be empty."
  exit 1
fi

read -rp "Give this device a name (e.g., 'iPhone 16 Pro'): " DEVICE_NAME
if [ -z "$DEVICE_NAME" ]; then
  echo "ERROR: Device name cannot be empty."
  exit 1
fi

# Check if UDID already exists in .env.json
if /usr/bin/python3 -c "
import json, sys
with open('$ENV_JSON') as f:
    data = json.load(f)
for d in data.get('devices', []):
    if d.get('udid') == '$UDID':
        print(f'Device already registered as: {d[\"name\"]}')
        sys.exit(1)
" 2>/dev/null; then
  : # not found, continue
else
  echo ""
  echo "This device is already in .env.json. You can build and install directly."
  echo ""
  echo "Build:"
  echo "  xcodebuild -project CBMPCNative/CBMPCNative.xcodeproj \\"
  echo "    -scheme CBMPCNative -sdk iphoneos -configuration Release \\"
  echo "    -destination 'generic/platform=iOS' -allowProvisioningUpdates build"
  echo ""
  echo "Install:"
  echo "  APP_PATH=\$(find ~/Library/Developer/Xcode/DerivedData/CBMPCNative-*/Build/Products/Release-iphoneos -name 'CBMPCNative.app' -maxdepth 1 | head -1)"
  echo "  xcrun devicectl device install app --device $UDID \"\$APP_PATH\""
  exit 0
fi

# Add device to .env.json
/usr/bin/python3 -c "
import json
with open('$ENV_JSON', 'r') as f:
    data = json.load(f)
if 'devices' not in data:
    data['devices'] = []
data['devices'].append({'name': '$DEVICE_NAME', 'udid': '$UDID'})
with open('$ENV_JSON', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

echo ""
echo "Added '$DEVICE_NAME' ($UDID) to .env.json"
echo ""
echo "--- Next steps ---"
echo ""
echo "1. Build for device (first build will register the device with Apple Developer):"
echo ""
echo "   xcodebuild -project CBMPCNative/CBMPCNative.xcodeproj \\"
echo "     -scheme CBMPCNative -sdk iphoneos -configuration Release \\"
echo "     -destination 'generic/platform=iOS' -allowProvisioningUpdates build"
echo ""
echo "2. Install to your device:"
echo ""
echo "   APP_PATH=\$(find ~/Library/Developer/Xcode/DerivedData/CBMPCNative-*/Build/Products/Release-iphoneos -name 'CBMPCNative.app' -maxdepth 1 | head -1)"
echo "   xcrun devicectl device install app --device $UDID \"\$APP_PATH\""
echo ""
echo "3. Launch:"
echo ""
echo "   xcrun devicectl device process launch --device $UDID xyz.atsignhandle.cb-mpc"
echo ""
echo "The -allowProvisioningUpdates flag automatically registers new devices"
echo "with the Apple Developer portal on first build."
