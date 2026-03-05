#!/usr/bin/env bash

# Quick installer - installs on all IPHONE_DEVICE_* configured in ~/.zshrc
# Usage: ./install-all-devices.sh

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment
source "$HOME/.zshrc" 2>/dev/null || true

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  CBMPCNative Fast Device Installer                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check configured devices
configured_devices=()
device_count=0

for i in 001 002 003; do
    var_name="IPHONE_DEVICE_$i"
    device_name="${!var_name}"

    if [ -n "$device_name" ]; then
        configured_devices+=("$device_name")
        echo -e "${GREEN}✓ IPHONE_DEVICE_$i${NC}: $device_name"
        ((device_count++))
    fi
done

if [ $device_count -eq 0 ]; then
    echo -e "${RED}Error: No IPHONE_DEVICE_* variables found in ~/.zshrc${NC}"
    echo ""
    echo "Add to ~/.zshrc:"
    echo "  export IPHONE_DEVICE_001=\"iPhone 15 Pro Max\""
    echo "  export IPHONE_DEVICE_002=\"iPhone 14 Pro\""
    echo "  export IPHONE_DEVICE_003=\"iPhone 13\""
    exit 1
fi

echo ""
echo -e "${YELLOW}Installing on $device_count device(s) without prompts...${NC}"
echo ""

cd "$PROJECT_DIR"

# Call main installer script with environment variables
# Use expect to auto-confirm prompts
expect -c "
    spawn ./install-on-devices.sh
    expect \"Use these * device(s)? (y/n):\" { send \"y\r\"; exp_continue }
    expect \"Proceed with installation? (y/n):\" { send \"y\r\"; exp_continue }
    expect eof
" || {
    # Fallback if expect not available
    echo -e "${YELLOW}Running without auto-confirmation (expect not installed)${NC}"
    ./install-on-devices.sh
}

echo ""
echo -e "${GREEN}Installation complete!${NC}"
