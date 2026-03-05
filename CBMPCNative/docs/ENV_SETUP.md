# Environment Setup Guide

## Current Configuration

Your `.zshrc` currently has:

```bash
export IPHONE_DEVICE_001="iPhone 15 Pro Max"
export IPHONE_DEVICE_003="iPhone 14 Pro"
```

**Missing:** `IPHONE_DEVICE_002` - This is for your second device.

## Quick Setup

### Step 1: Find Your Device Name

Connect your third iPhone and run:

```bash
xcodebuild -showdestinations -scheme CBMPCNative -project CBMPCNative.xcodeproj 2>/dev/null | grep "iOS" | grep -v "Simulator"
```

Example output:
```
{'platform:iOS','name:iPhone 14','id:00008060-001...'}
```

The device name is what appears after `'name:`.

### Step 2: Add to .zshrc

Open your `.zshrc`:

```bash
nano ~/.zshrc
```

Find the existing `IPHONE_DEVICE` lines around line 291:

```bash
# Around line 291
export IPHONE_DEVICE_001="iPhone 15 Pro Max"
export IPHONE_DEVICE_002="YOUR_DEVICE_NAME_HERE"    # Add this line
export IPHONE_DEVICE_003="iPhone 14 Pro"
```

Replace `YOUR_DEVICE_NAME_HERE` with your actual device name.

### Step 3: Reload .zshrc

```bash
source ~/.zshrc
```

Verify it loaded:

```bash
echo $IPHONE_DEVICE_002
```

Should print your device name.

## Usage

### Automatic Installation (Uses Environment Variables)

After setting up the environment variables, installation becomes simple:

#### Interactive Mode (Recommended)
```bash
./install-on-devices.sh
```

The script will:
- ✓ Detect your environment variables
- ✓ Display all 3 configured devices
- ✓ Ask for confirmation
- ✓ Install automatically

#### Non-Interactive Mode (Full Auto)
```bash
./install-all-devices.sh
```

Installs on all configured devices without any prompts.

## Example Configuration

Here's what your complete setup should look like in `~/.zshrc`:

```bash
# iPhone Device Configuration
export IPHONE_DEVICE_001="iPhone 15 Pro Max"      # Your primary device
export IPHONE_DEVICE_002="iPhone 14 Pro"          # Your secondary device
export IPHONE_DEVICE_003="iPhone 13"              # Your tertiary device
```

## Commands Quick Reference

```bash
# Interactive: See configured devices and choose which to install on
./install-on-devices.sh

# Non-interactive: Install on all configured devices immediately
./install-all-devices.sh

# Manual: Build for specific device
xcodebuild build \
  -scheme CBMPCNative \
  -project CBMPCNative.xcodeproj \
  -destination "platform=iOS,name=iPhone 15 Pro Max" \
  -configuration Release

# List all connected devices
xcodebuild -showdestinations -scheme CBMPCNative -project CBMPCNative.xcodeproj
```

## Troubleshooting

### "No IPHONE_DEVICE_* variables found"
**Solution:** Run `source ~/.zshrc` and verify with:
```bash
echo $IPHONE_DEVICE_001
echo $IPHONE_DEVICE_002
echo $IPHONE_DEVICE_003
```

### Device name not matching
**Solution:** Device names are case-sensitive. Use exact names from:
```bash
xcodebuild -showdestinations -scheme CBMPCNative -project CBMPCNative.xcodeproj
```

### Can't find device in output
**Solution:** Make sure device is connected and shows:
```bash
ios-deploy --detect
```

## Advanced: Shell Functions

Optionally, add these functions to your `.zshrc` for even faster usage:

```bash
# Install on all devices
cb-install-all() {
    cd ~/Developer/cb-mpc/.worktrees/ios-integration-phase-1/CBMPCNative
    ./install-all-devices.sh
}

# Install with device selection
cb-install() {
    cd ~/Developer/cb-mpc/.worktrees/ios-integration-phase-1/CBMPCNative
    ./install-on-devices.sh
}

# Quick device list
cb-devices() {
    echo "Configured devices:"
    echo "  1. $IPHONE_DEVICE_001"
    echo "  2. $IPHONE_DEVICE_002"
    echo "  3. $IPHONE_DEVICE_003"
}

# Build for all devices
cb-build-all() {
    cd ~/Developer/cb-mpc/.worktrees/ios-integration-phase-1/CBMPCNative
    xcodebuild build -scheme CBMPCNative -project CBMPCNative.xcodeproj \
        -destination "platform=iOS,name=$IPHONE_DEVICE_001" \
        -configuration Release
    xcodebuild build -scheme CBMPCNative -project CBMPCNative.xcodeproj \
        -destination "platform=iOS,name=$IPHONE_DEVICE_002" \
        -configuration Release
    xcodebuild build -scheme CBMPCNative -project CBMPCNative.xcodeproj \
        -destination "platform=iOS,name=$IPHONE_DEVICE_003" \
        -configuration Release
}
```

Then use:
```bash
cb-install          # Interactive installation
cb-install-all      # Install all 3 devices automatically
cb-devices          # Show configured devices
cb-build-all        # Build for all devices
```

## Next Steps

1. **Add IPHONE_DEVICE_002** to your `.zshrc` with your middle device name
2. **Reload** with `source ~/.zshrc`
3. **Test** with `./install-on-devices.sh`
4. **Install** with `./install-all-devices.sh`

Done! Your environment is now fully configured for multi-device installation. 🎉
