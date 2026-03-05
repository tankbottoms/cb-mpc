# Multi-Device Installation Guide

## Prerequisites

### 1. Device Requirements
- **iOS Version**: iOS 13.0 or later
- **Storage**: At least 200 MB free space per device
- **USB Connection**: Each device must be connected via USB to your Mac
- **Trust**: Device must trust your Mac (tap "Trust" when first connected)

### 2. Mac Setup

#### Xcode Installation
```bash
xcode-select --install
```

#### Enable Developer Mode on Devices
On each iPhone, after connecting:
1. Go to **Settings** → **Privacy & Security** → **Developer Mode**
2. Toggle **Developer Mode** ON
3. Tap **Restart** when prompted
4. On your Mac, run the installation script (see below)

#### Optional: Install ios-deploy for Better Device Detection
```bash
brew install ios-deploy
```

## Quick Start

### Step 1: Connect Your Devices
Plug all three iPhones into your Mac via USB. You should see a Trust dialog on each device:
- Tap **Trust** on each device
- If you don't see the trust dialog, unlock the device and try again

### Step 2: Enable Developer Mode
On each connected device:
1. **Settings** → **Privacy & Security** → **Developer Mode**
2. Toggle **ON** (toggle switch turns green)
3. **Restart** the device when prompted

### Step 3: Run the Installation Script
```bash
cd CBMPCNative
./install-on-devices.sh
```

The script will:
1. ✓ Detect all connected iOS devices
2. ✓ List available devices with numbers
3. ✓ Ask which devices to install on (or install on all)
4. ✓ Build the app for each device
5. ✓ Install the app on each device
6. ✓ Provide trust certificate instructions

### Step 4: Trust Developer Certificate (on each device)
After the script completes successfully:

On each iPhone:
1. Go to **Settings**
2. Tap **General**
3. Scroll down and tap **Device Management**
4. Select your Apple ID (usually shows as "Apple Development: [email]")
5. Tap **Trust**
6. Confirm in the dialog

### Step 5: Launch the App
After trusting, the app icon appears on your Home Screen:
- App name: **CBMPCNative**
- Icon: Cryptographic key symbol

## Troubleshooting

### "No iOS devices detected"
**Solution:**
```bash
# Disconnect all devices
# Reconnect one device at a time
# Ensure you tap "Trust" on each device
# Restart the device if trust dialog doesn't appear
```

### "Device is already locked"
**Solution:**
```bash
# Unlock the device
# Tap "Trust" when prompted
# Try installation again
```

### Build Fails: "CIFilter has no member 'qrCodeGenerator'"
This means you're using an older iOS deployment target. The script should handle this automatically, but if needed:
```bash
# The QRCodeView uses the correct CoreImage API (CIQRCodeGenerator)
# Ensure iOS 13.0+ deployment target in Xcode
```

### Installation Fails: "Unable to launch CFBundleIdentifier"
**Solution:**
```bash
# 1. Trust the developer certificate on the device (see Step 4 above)
# 2. Wait 30 seconds for the certificate to register
# 3. Try launching the app from the Home Screen manually
```

### Device not appearing in list
**Solution:**
```bash
# Method 1: Manually select device in Xcode
xcode-select -p
# Should show: /Applications/Xcode.app/Contents/Developer

# Method 2: Use ios-deploy to detect
ios-deploy --detect

# Method 3: Disconnect and reconnect the device
```

## Advanced: Manual Installation

If the script doesn't work, install manually:

### For a Single Device
```bash
# List available devices
xcodebuild -showdestinations -scheme CBMPCNative -project CBMPCNative.xcodeproj

# Build (replace "Device Name" with actual device name)
xcodebuild build \
  -scheme CBMPCNative \
  -project CBMPCNative.xcodeproj \
  -destination "platform=iOS,name=Device Name" \
  -configuration Release

# Install
xcodebuild install \
  -scheme CBMPCNative \
  -project CBMPCNative.xcodeproj \
  -destination "platform=iOS,name=Device Name" \
  -configuration Release
```

### Using ios-deploy
```bash
# Find device IDs
ios-deploy --detect

# Install on specific device (replace DEVICE_ID)
ios-deploy --bundle CBMPCNative.app --id DEVICE_ID
```

## What Gets Installed

### App Bundle Contents
- **Binary**: ARM64 architecture (device native)
- **Frameworks**: cbmpc.xcframework (cryptographic library)
- **Resources**: UI assets, launch screen, Info.plist
- **Code**: All Swift UI components (Sign, QR, Dashboard, etc.)

### Storage Usage
- App size: ~50-100 MB
- On first launch: Creates local database (~5 MB)
- CloudKit sync: Optional, ~1-10 MB per user profile

## Post-Installation

### Verify Installation
1. Open **Settings** → **General** → **iPhone Storage**
2. Scroll to find **CBMPCNative**
3. Should show ~50-100 MB used

### First Launch
- App auto-seeds with demo Ethereum key
- Creates local SQLite database
- Can add additional keys via "+" button

### Update Process
To push updates to devices after code changes:
```bash
# Just run the script again
./install-on-devices.sh
# Select "yes" to install on specific devices
```

## Security Notes

### Developer Certificate
- Only valid for local development
- Automatically generated when you first build
- Never shared or uploaded
- Each Mac generates its own certificate

### App Signing
- Apps are self-signed for development
- Cannot be shared between Macs
- Only work on devices connected to the building Mac
- Expires after 7 days (auto-renews on rebuild)

### Data Privacy
- All key material stays on device
- No data uploaded to servers unless you explicitly submit to signing server
- Uses iOS Secure Enclave for key storage when available

## Support

If you encounter issues:

1. **Check device connection**: `ios-deploy --detect`
2. **Check Xcode setup**: `xcode-select -p`
3. **Review device logs**:
   ```bash
   # View device console logs
   xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```
4. **Clear derived data and rebuild**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/CBMPCNative*
   ./install-on-devices.sh
   ```

## Device Names

Your three devices should appear as:
- Device 1: `Mark's iPhone` (or custom name)
- Device 2: `[Device Name]`
- Device 3: `[Device Name]`

To check device names:
```bash
xcodebuild -showdestinations -scheme CBMPCNative -project CBMPCNative.xcodeproj | grep "iOS" | grep -v "Simulator"
```

To rename a device in Xcode:
1. In Xcode: **Window** → **Devices and Simulators**
2. Select the device
3. Click the device name to edit
