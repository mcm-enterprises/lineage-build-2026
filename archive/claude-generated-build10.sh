#!/bin/bash

# ============================================================================
# LineageOS 22.1 Production Script for Pixel 8 Pro (husky)
# Handles: No Source, Partial Sync, Corrupted Metadata, Stale Locks
# ============================================================================

# --- 1. CONFIGURATION ---
DEVICE="husky"
BRANCH="lineage-22.1"
BUILD_DIR="/media/BIG_STORAGE/lineageOS/android_source/LINEAGE_22_1"
EXTRACTED_IMAGES="/media/BIG_STORAGE/lineageOS/images/extracted"
JOBS=$(nproc --all)

# Colors for scannability
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
CYAN='\033[0;36m'; MAGENTA='\033[1;35m'; BOLD='\033[1m'; NC='\033[0m'

# Parse arguments
SKIP_SYNC=false
for arg in "$@"; do [[ "$arg" == "--skip-sync" ]] && SKIP_SYNC=true; done

# --- 2. OS & AOSP COMPATIBILITY ---
# Fix AppArmor for Ubuntu 25.10 (needed for Soong/sbox)
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true

# Set explicit build date to bypass 2026 timestamp checks
export OVERRIDE_BUILD_DATE=1743465600
export BUILD_DATETIME_CHECK=false
export LC_ALL=C

echo -e "\n${BOLD}${MAGENTA}🚀 PIXEL 8 PRO PRODUCTION BUILD STARTING${NC}\n"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit 1

# --- 3. LOCK & CORRUPTION CLEANUP ---
echo -e "${CYAN}[→] Cleaning stale locks and corrupted XMLs...${NC}"
find .repo -name "*.lock" -delete 2>/dev/null
find . -name "index.lock" -delete 2>/dev/null

# Purge 0-byte XML files that crash the build parser
find vendor/google/husky -type f -size 0 -name "*.xml" -delete
rm -f vendor/google/husky/proprietary/system_ext/etc/default-permissions/default-permissions-euiccpixel.xml

# --- 4. MANIFEST IDENTITY REPAIR ---
# The "Magic Fix": Finding the EXACT name used in the official manifest
if [ -d ".repo/manifests" ]; then
    echo -e "${CYAN}[→] Resolving manifest project naming...${NC}"
    # This searches the active manifest for the project mapping to device/google/husky
    REAL_NAME=$(grep -r "path=\"device/google/husky\"" .repo/manifests | sed -n 's/.*name="\([^"]*\)".*/\1/p' | head -n 1)
    
    if [ -n "$REAL_NAME" ]; then
        mkdir -p .repo/local_manifests
        cat <<EOF > .repo/local_manifests/husky.xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remove-project name="$REAL_NAME" />
  <project name="$REAL_NAME" path="device/google/husky" remote="github" revision="$BRANCH" />
</manifest>
EOF
        echo -e "${GREEN}[✓] Identity Found: $REAL_NAME. Local manifest updated.${NC}"
    fi
fi

# --- 5. SOURCE INITIALIZATION & SYNC ---
if [ ! -d ".repo" ]; then
    echo -e "${YELLOW}[!] Source missing. Bootstrapping repo...${NC}"
    repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs
    SKIP_SYNC=false 
fi

if [ "$SKIP_SYNC" = false ]; then
    echo -e "${CYAN}[→] Syncing Source (Robust Mode)...${NC}"
    repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags --fail-fast || {
        echo -e "${RED}[✗] Parallel sync failed. Retrying with stability mode...${NC}"
        repo sync -c -j1 --force-sync
    }
else
    echo -e "${GREEN}[✓] --skip-sync: Using existing tree.${NC}"
fi

# --- 6. PROPRIETARY BLOB RESCUE ---

echo -e "${CYAN}[→] Rescuing blobs from factory images...${NC}"
MOUNT_BASE="/tmp/husky_mounts"
mkdir -p "$MOUNT_BASE/system" "$MOUNT_BASE/system_ext" "$MOUNT_BASE/product" "$MOUNT_BASE/vendor"

for img in system system_ext product vendor; do
    if [ -f "$EXTRACTED_IMAGES/$img.img" ]; then
        sudo mount -t erofs,ext4 -o ro "$EXTRACTED_IMAGES/$img.img" "$MOUNT_BASE/$img" 2>/dev/null
    fi
done

PROPRIETARY_LIST="device/google/shusky/husky/proprietary-files.txt"
if [ -f "$PROPRIETARY_LIST" ]; then
    grep -v '^#' "$PROPRIETARY_LIST" | grep -v '^$' | sed 's/^-//' | while read -r line; do
        dest=$(echo "$line" | cut -d':' -f1 | cut -d'|' -f1)
        src_name=$(basename "$(echo "$line" | sed 's/.*[:|]//')")
        target_path="vendor/google/husky/proprietary/$dest"
        
        if [ ! -s "$target_path" ]; then
            found_path=$(sudo find "$MOUNT_BASE" -type f -name "$src_name" | head -n 1)
            if [ -n "$found_path" ]; then
                mkdir -p "$(dirname "$target_path")"
                sudo cp "$found_path" "$target_path"
                sudo chmod 644 "$target_path"
            fi
        fi
    done
fi
sudo umount -R "$MOUNT_BASE" 2>/dev/null

# --- 7. FINAL BUILD LAUNCH ---
source build/envsetup.sh
breakfast "$DEVICE"

# Unset restricted variables to prevent tool path collisions
unset CC_WRAPPER
unset CCACHE_EXEC
unset USE_CCACHE



echo -e "${GREEN}[🚀] LAUNCHING BACON...${NC}"
m bacon -j"$JOBS"