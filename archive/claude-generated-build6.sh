#!/bin/bash

# LineageOS 22.1 Build Script for Pixel 8 Pro (husky)
# VERSION: Ninja Error Fix & CarrierSettings Patch

# Configuration
DEVICE="husky"
SRC_NAME="android_source/LINEAGE_22_1"
BUILD_DIR="/media/BIG_STORAGE/lineageOS/$SRC_NAME"
CCACHE_DIR="/media/BIG_STORAGE/lineageOS/.ccache"
UNPACK_DIR="/media/BIG_STORAGE/lineageOS/images/extracted"

# --- SYSTEM FIXES ---
export USE_CCACHE=1
export CCACHE_DIR="$CCACHE_DIR"
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true

cd "$BUILD_DIR" || exit 1

# --- STEP 4 FIX: Ensure the file Ninja wants actually exists ---
SENTINEL="vendor/google/husky/proprietary/product/etc/CarrierSettings/reachmobileatt_us.pb"

if [ ! -f "$SENTINEL" ]; then
    echo -e "\033[1;33m[⚠] Missing Ninja target: $SENTINEL\033[0m"
    echo -e "\033[1;36m[→] Attempting Python-based re-extraction...\033[0m"
    
    cd device/google/shusky
    # Using the python extractor often handles nested CarrierSettings better
    python3 ./extract-files.py "$UNPACK_DIR"
    
    cd "$BUILD_DIR"
fi

# If it's STILL missing, we create a placeholder to let the build finish
if [ ! -f "$SENTINEL" ]; then
    echo -e "\033[1;31m[✗] File still missing. Creating dummy placeholder to bypass Ninja error...\033[0m"
    mkdir -p $(dirname "$SENTINEL")
    touch "$SENTINEL"
fi

# --- START BUILD ---
source build/envsetup.sh
breakfast "$DEVICE"



echo -e "\033[1;32m[✓] Environment ready. Launching build...\033[0m"
m -j$(nproc --all) bacon