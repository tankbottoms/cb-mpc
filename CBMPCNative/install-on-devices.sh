#!/usr/bin/env bash

# CBMPCNative Multi-Device Installation Script
# Builds and installs the app on multiple iOS devices

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_FILE="${PROJECT_DIR}/CBMPCNative.xcodeproj"
SCHEME="CBMPCNative"
CONFIGURATION="Release"
BUILD_DIR="${PROJECT_DIR}/build"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  CBMPCNative Multi-Device Installation Tool            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Load and display environment configuration
if [ -f "$HOME/.zshrc" ]; then
    source "$HOME/.zshrc" 2>/dev/null || true

    if [ -n "$IPHONE_DEVICE_001" ] || [ -n "$IPHONE_DEVICE_002" ] || [ -n "$IPHONE_DEVICE_003" ]; then
        echo -e "${GREEN}✓ Environment Variables Loaded from ~/.zshrc${NC}"
        [ -n "$IPHONE_DEVICE_001" ] && echo "  • IPHONE_DEVICE_001: $IPHONE_DEVICE_001"
        [ -n "$IPHONE_DEVICE_002" ] && echo "  • IPHONE_DEVICE_002: $IPHONE_DEVICE_002"
        [ -n "$IPHONE_DEVICE_003" ] && echo "  • IPHONE_DEVICE_003: $IPHONE_DEVICE_003"
        echo ""
    fi
fi

# Function to list available devices
list_devices() {
    echo -e "${YELLOW}Detecting connected iOS devices...${NC}"
    echo ""

    # Use xcodebuild to get device list
    local devices=$(xcodebuild -showdestinations -scheme "$SCHEME" -project "$PROJECT_FILE" 2>/dev/null | grep "platform:iOS" | grep -v "Simulator")

    if [ -z "$devices" ]; then
        echo -e "${RED}No iOS devices detected. Please connect devices and try again.${NC}"
        return 1
    fi

    echo -e "${GREEN}Connected Devices:${NC}"
    echo "$devices" | nl
    echo ""
}

# Function to extract device name from destination string
extract_device_name() {
    echo "$1" | sed -n "s/.*name:\([^,]*\).*/\1/p" | tr -d ' '
}

# Function to build for a device
build_for_device() {
    local device_name=$1

    echo -e "${BLUE}Building for device: ${YELLOW}${device_name}${NC}"

    xcodebuild build \
        -scheme "$SCHEME" \
        -project "$PROJECT_FILE" \
        -destination "platform=iOS,name=${device_name}" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "${BUILD_DIR}/${device_name}" \
        -allowProvisioningUpdates \
        2>&1 | grep -E "(Building|Compiling|Linking|error:|warning:|provisioning)" || true

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}✓ Build succeeded for ${device_name}${NC}"
        return 0
    else
        echo -e "${RED}✗ Build failed for ${device_name}${NC}"
        return 1
    fi
}

# Function to install on device
install_on_device() {
    local device_name=$1

    echo -e "${BLUE}Installing app on: ${YELLOW}${device_name}${NC}"

    xcodebuild install \
        -scheme "$SCHEME" \
        -project "$PROJECT_FILE" \
        -destination "platform=iOS,name=${device_name}" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "${BUILD_DIR}/${device_name}" \
        2>&1 | grep -E "(Installing|installed|error:)" || true

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}✓ Installation succeeded for ${device_name}${NC}"
        return 0
    else
        echo -e "${RED}✗ Installation failed for ${device_name}${NC}"
        return 1
    fi
}

# Function to get device IDs
get_device_ids() {
    local device_name=$1

    # Try ios-deploy if available
    if command -v ios-deploy &> /dev/null; then
        ios-deploy --detect | grep -i "$device_name" | head -1
    else
        echo "$device_name"
    fi
}

# Load environment variables from .zshrc if available
load_device_env_vars() {
    if [ -f "$HOME/.zshrc" ]; then
        source "$HOME/.zshrc" 2>/dev/null || true
    fi
}

# Check if device environment variables are configured
check_env_devices() {
    local env_devices=()

    for i in 001 002 003; do
        local var_name="IPHONE_DEVICE_$i"
        local device_name="${!var_name}"

        if [ -n "$device_name" ]; then
            env_devices+=("$device_name")
        fi
    done

    printf '%s\n' "${env_devices[@]}"
}

# Main installation flow
main() {
    # Check prerequisites
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    if ! xcodebuild -version > /dev/null 2>&1; then
        echo -e "${RED}Error: Xcode is not properly configured${NC}"
        exit 1
    fi

    if [ ! -f "$PROJECT_FILE/project.pbxproj" ]; then
        echo -e "${RED}Error: Project file not found at ${PROJECT_FILE}${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Xcode is ready${NC}"
    echo -e "${GREEN}✓ Project file found${NC}"
    echo ""

    # Load environment variables
    load_device_env_vars

    # Check for environment-configured devices
    local env_devices=()
    local target_devices=()

    for i in 001 002 003; do
        local var_name="IPHONE_DEVICE_$i"
        local device_name="${!var_name}"
        if [ -n "$device_name" ]; then
            env_devices+=("$device_name")
        fi
    done

    if [ ${#env_devices[@]} -gt 0 ]; then
        echo -e "${GREEN}Detected IPHONE_DEVICE_* environment variables from .zshrc${NC}"
        echo -e "${BLUE}Configured devices:${NC}"
        local idx=1
        for device in "${env_devices[@]}"; do
            echo "  $idx. $device"
            ((idx++))
        done
        echo ""
        read -p "Use these ${#env_devices[@]} device(s)? (y/n): " use_env

        if [[ "$use_env" == "y" || "$use_env" == "Y" ]]; then
            # Verify these devices are actually connected
            list_devices
            target_devices=("${env_devices[@]}")
            echo ""
        else
            echo "Proceeding with device selection..."
            list_devices
            # Fall through to manual selection
            target_devices=()
        fi
    fi

    # If not using env variables, do manual selection
    if [ ${#target_devices[@]} -eq 0 ]; then
        # Get raw device list for processing
        local device_list=$(xcodebuild -showdestinations -scheme "$SCHEME" -project "$PROJECT_FILE" 2>/dev/null | grep "platform:iOS" | grep -v "Simulator")
        local device_array=()
        local counter=1

        while IFS= read -r line; do
            device_array+=("$line")
            ((counter++))
        done <<< "$device_list"

        # Ask user which devices to install on
        echo -e "${YELLOW}Which devices would you like to install on?${NC}"
        echo "Enter device numbers separated by spaces (e.g., '1 2 3' for all three)"
        echo "Or press Enter to install on all detected devices"
        read -p "Device numbers: " user_input

        # Determine target devices
        if [ -z "$user_input" ]; then
            # Install on all devices
            target_devices=("${device_array[@]}")
            echo -e "${BLUE}Installing on all ${#target_devices[@]} device(s)${NC}"
        else
            # Parse user input
            for num in $user_input; do
                if [ "$num" -le "${#device_array[@]}" ] && [ "$num" -gt 0 ]; then
                    target_devices+=("${device_array[$((num-1))]}")
                fi
            done
        fi
    fi

    if [ ${#target_devices[@]} -eq 0 ]; then
        echo -e "${RED}No valid devices selected${NC}"
        exit 1
    fi

    echo ""
    echo -e "${BLUE}Installation Plan:${NC}"
    echo "Devices to install: ${#target_devices[@]}"
    for device in "${target_devices[@]}"; do
        # Check if it's a full destination string or just a device name
        if [[ "$device" == *"platform:iOS"* ]]; then
            local name=$(extract_device_name "$device")
        else
            local name="$device"
        fi
        echo "  • $name"
    done
    echo ""

    read -p "Proceed with installation? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Installation cancelled"
        exit 0
    fi

    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Building and Installing...                            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Track results
    local successful_installs=()
    local failed_installs=()

    # Process each device
    for device in "${target_devices[@]}"; do
        # Check if it's a full destination string or just a device name
        local device_name
        if [[ "$device" == *"platform:iOS"* ]]; then
            device_name=$(extract_device_name "$device")
        else
            device_name="$device"
        fi

        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "Device: $device_name"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        if build_for_device "$device_name"; then
            echo ""
            if install_on_device "$device_name"; then
                successful_installs+=("$device_name")
            else
                failed_installs+=("$device_name")
            fi
        else
            failed_installs+=("$device_name")
        fi
    done

    # Print summary
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Installation Summary                                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ${#successful_installs[@]} -gt 0 ]; then
        echo -e "${GREEN}✓ Successfully installed on ${#successful_installs[@]} device(s):${NC}"
        for device in "${successful_installs[@]}"; do
            echo "  • $device"
        done
        echo ""
    fi

    if [ ${#failed_installs[@]} -gt 0 ]; then
        echo -e "${RED}✗ Failed on ${#failed_installs[@]} device(s):${NC}"
        for device in "${failed_installs[@]}"; do
            echo "  • $device"
        done
        echo ""
    fi

    # Trust certificate instructions
    if [ ${#successful_installs[@]} -gt 0 ]; then
        echo -e "${YELLOW}Important: Trust the Developer Certificate${NC}"
        echo ""
        echo "On each device, go to:"
        echo "  ${BLUE}Settings${NC} → ${BLUE}General${NC} → ${BLUE}Device Management${NC}"
        echo ""
        echo "Then select your Apple ID and tap ${BLUE}Trust${NC}"
        echo ""
        echo "After trusting, you can launch the app from the Home Screen."
        echo ""
    fi

    # Return appropriate exit code
    if [ ${#failed_installs[@]} -eq 0 ]; then
        echo -e "${GREEN}All installations completed successfully!${NC}"
        exit 0
    else
        echo -e "${RED}Some installations failed. Please check the output above.${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
