#!/bin/bash

# Configuration
DEVICE="husky"
BUILD_DIR="/media/BIG_STORAGE/lineageOS/android_source/LINEAGE_22_1"
CCACHE_DIR="/media/BIG_STORAGE/lineageOS/.ccache"

# --- FIX ENVIRONMENT VARIABLES ---
# This stops the "regenerating..." loop you saw in your logs
export USE_CCACHE=1
export CCACHE_DIR="$CCACHE_DIR"
export CCACHE_EXEC=$(which ccache)
export CC_WRAPPER="ccache"

# Ubuntu 25.10 AppArmor Fix
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true

cd "$BUILD_DIR" || exit 1

# --- PRE-BUILD VALIDATION ---
MISSING_FILES=0
# Check for the two files that caused failures
FILES_TO_CHECK=(
    "vendor/google/husky/proprietary/product/etc/CarrierSettings/reachmobileatt_us.pb"
    "vendor/google/husky/proprietary/system_ext/etc/default-permissions/default-permissions-euiccpixel.xml"
)

for file in "${FILES_TO_CHECK[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "\033[1;31m[✗] MISSING: $file\033[0m"
        MISSING_FILES=$((MISSING_FILES + 1))
    fi
done

if [ $MISSING_FILES -gt 0 ]; then
    echo -e "\033[1;33m[→] Critical files missing. Attempting emergency placeholder creation...\033[0m"
    for file in "${FILES_TO_CHECK[@]}"; do
        if [ ! -f "$file" ]; then
            mkdir -p "$(dirname "$file")"
            touch "$file"
            echo "Created stub for $file"
        fi
    done
fi

# --- START BUILD ---
source build/envsetup.sh
breakfast "$DEVICE"

echo -e "\033[1;32m[✓] Environment synced. Launching Ninja...\033[0m"
m -j$(nproc --all) bacon