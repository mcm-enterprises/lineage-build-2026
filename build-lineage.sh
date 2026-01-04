#!/bin/bash

# LineageOS 22.1 Build Script for Pixel 8 Pro (husky)
# Final "Obsolete-Fix" Edition

# --- COLORS ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
CYAN='\033[0;36m'; MAGENTA='\033[1;35m'; BOLD='\033[1m'; NC='\033[0m'

# --- CONFIG ---
DEVICE="husky"
SRC_NAME="android_source/LINEAGE_22_1"
BUILD_DIR="/media/BIG_STORAGE/lineageOS/$SRC_NAME"
EXTRACTED_IMAGES="/media/BIG_STORAGE/lineageOS/images/extracted"
JOBS=$(nproc --all)

# --- UBUNTU 25.10 DATE FIX ---
function date() {
  if [[ "$*" == *"TZ=\"GMT\""* ]]; then
    local args=$(echo "$*" | sed 's/TZ="GMT"//g')
    command date $args
  else
    command date "$@"
  fi
}
export -f date

# OS Fixes
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true
export OVERRIDE_BUILD_DATE=$(date -d "2025-04-01" +%s)
export BUILD_DATETIME_CHECK=false
export LC_ALL=C

echo -e "\n${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${MAGENTA}║   LineageOS 22.1 Build Script for Pixel 8 Pro (husky)     ║${NC}"
echo -e "${BOLD}${MAGENTA}║           Final Obsolete-Path & Search Fix                 ║${NC}"
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}\n"

# --- STEP 1: FIXED BULK RESCUE ---
echo -e "${CYAN}[→] STEP 1: Mounting and Rescuing Blobs (Fixed Search)...${NC}"
MOUNT_BASE="/tmp/husky_mounts"
mkdir -p "$MOUNT_BASE/system" "$MOUNT_BASE/system_ext" "$MOUNT_BASE/product" "$MOUNT_BASE/vendor"

sudo mount -t erofs,ext4 -o ro "$EXTRACTED_IMAGES/system.img" "$MOUNT_BASE/system" 2>/dev/null
sudo mount -t erofs,ext4 -o ro "$EXTRACTED_IMAGES/system_ext.img" "$MOUNT_BASE/system_ext" 2>/dev/null
sudo mount -t erofs,ext4 -o ro "$EXTRACTED_IMAGES/product.img" "$MOUNT_BASE/product" 2>/dev/null
sudo mount -t erofs,ext4 -o ro "$EXTRACTED_IMAGES/vendor.img" "$MOUNT_BASE/vendor" 2>/dev/null



PROPRIETARY_LIST="$BUILD_DIR/device/google/shusky/husky/proprietary-files.txt"

if [ -f "$PROPRIETARY_LIST" ]; then
    # We focus on the files Ninja reported as missing
    CLEAN_LIST=$(grep -v '^#' "$PROPRIETARY_LIST" | grep -E '\.(xml|rc|pb|txt|img)$' | sed 's/^-//')

    for entry in $CLEAN_LIST; do
        dest_rel_path=$(echo "$entry" | cut -d':' -f1 | cut -d'|' -f1)
        target_filename=$(echo "$entry" | sed 's/.*[:|]//')
        full_dest_path="$BUILD_DIR/vendor/google/husky/proprietary/$dest_rel_path"
        
        if [ ! -f "$full_dest_path" ]; then
            # Using -name for just the filename to avoid the 'separator' warning
            base_search=$(basename "$target_filename")
            FOUND=$(sudo find "$MOUNT_BASE" -type f -name "$base_search" | head -n 1)

            if [ -n "$FOUND" ]; then
                mkdir -p "$(dirname "$full_dest_path")"
                sudo cp "$FOUND" "$full_dest_path"
                sudo chmod 644 "$full_dest_path"
                echo -e "${GREEN}    [✓] Rescued: $base_search${NC}"
            fi
        fi
    done
fi

sudo umount -R "$MOUNT_BASE" 2>/dev/null

# --- STEP 2: BUILD CONFIG (CCACHE REMOVED FOR STABILITY) ---
echo -e "\n${CYAN}[→] STEP 2: Initializing Build Environment (Strict Path)...${NC}"
cd "$BUILD_DIR" || exit 1

# Completely unset ccache to bypass "Disallowed PATH tool" errors
unset USE_CCACHE
unset CCACHE_DIR
unset CCACHE_EXEC
unset CC_WRAPPER
unset TEMPORARY_DISABLE_PATH_RESTRICTIONS

source build/envsetup.sh
breakfast "$DEVICE"

# --- STEP 3: LAUNCH ---
echo -e "\n${CYAN}[→] STEP 3: Starting Ninja build...${NC}"

# We use 'm bacon' to generate the final OTA zip
if m bacon -j"$JOBS"; then
    echo -e "\n${BOLD}${GREEN}SUCCESS! BUILD COMPLETED.${NC}"
    echo -e "${BOLD}Your flashable zip is here:${NC}"
    ls -lh out/target/product/husky/lineage-*.zip
else
    echo -e "\n${RED}[✗] Build failed at the final stage.${NC}"
    exit 1
fi

