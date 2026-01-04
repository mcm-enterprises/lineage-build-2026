#!/bin/bash

# LineageOS Build Script for Pixel 8 Pro (husky)
# Supports variable versions (Default: 22.1)

# --- COLORS ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
CYAN='\033[0;36m'; MAGENTA='\033[1;35m'; BOLD='\033[1m'; NC='\033[0m'

# --- CONFIG ---
# --- CONFIG ---
# Default Version
VERSION="22.1"
SKIP_SYNC=false
CLEAN_FLAG=false

# --- ARGUMENTS PARSING ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-sync)
      SKIP_SYNC=true
      shift # past argument
      ;;
    --clean)
      CLEAN_FLAG=true
      shift # past argument
      ;;
    *)
      # Assume any non-flag argument is the version
      VERSION="$1"
      shift # past value
      ;;
  esac
done

# Convert dots to underscores for directory naming (e.g. 22.1 -> 22_1)
VERSION_DIR_SUFFIX=${VERSION//./_}

DEVICE="husky"
SRC_NAME="android_source/LINEAGE_${VERSION_DIR_SUFFIX}"

# Automatically detect the script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/$SRC_NAME"
EXTRACTED_IMAGES="$SCRIPT_DIR/images/extracted"
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
echo -e "${BOLD}${MAGENTA}║   LineageOS ${VERSION} Build Script for Pixel 8 Pro (husky)      ║${NC}"
echo -e "${BOLD}${MAGENTA}║           Final Obsolete-Path & Search Fix                 ║${NC}"
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}\n"

# --- STEP 0: CHECK/INIT SOURCE ---
# Function: Robust Sync
function robust_sync() {
    echo -e "${CYAN}[→] Syncing source code (Attempting robust sync)...${NC}"
    MAX_RETRIES=3
    count=0
    
    while [ $count -lt $MAX_RETRIES ]; do
        # We capture both stdout and stderr to a temp file to parse errors
        # Added --verbose so the user can see what is happening real-time
        if repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags --verbose 2> >(tee /tmp/repo_sync_error.log >&2); then
            echo -e "${GREEN}[✓] Sync completed successfully.${NC}"
            return 0
        else
            current_attempt=$((count + 1))
            echo -e "${YELLOW}[!] Sync failed (Attempt $current_attempt/$MAX_RETRIES). Checking for corruption...${NC}"
            
            # Check for specific "checkout state" corruption
            CORRUPT_PATH=$(grep "unsupported checkout state" /tmp/repo_sync_error.log | awk -F': ' '{print $2}' | awk '{print $1}')
            
            if [ -n "$CORRUPT_PATH" ] && [ -d "$CORRUPT_PATH" ]; then
                echo -e "${RED}[☢] Detected corrupted repo at: $CORRUPT_PATH${NC}"
                echo -e "${RED}    Deleting and forcing re-download...${NC}"
                rm -rf "$CORRUPT_PATH"
            else
                echo -e "${YELLOW}[?] No auto-fixable corruption detected. Retrying standard sync...${NC}"
                find .repo -name "*.lock" -delete 2>/dev/null
            fi
            
            count=$((count + 1))
            sleep 5
        fi
    done
    
    echo -e "${RED}[✗] Sync failed after multiple attempts. Manual intervention required.${NC}"
    return 1
}

# Ensure directory exists
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit 1

# Check if we need to init
if [ ! -d ".repo" ]; then
    echo -e "${YELLOW}[!] Source directory uninitialized.${NC}"
    echo -e "${CYAN}[→] Initializing $SRC_NAME for LineageOS $VERSION...${NC}"
    repo init -u https://github.com/LineageOS/android.git -b "lineage-${VERSION}" --git-lfs
fi

# Run Sync (Unless skipped)
if [ "$SKIP_SYNC" = false ]; then
    robust_sync || exit 1
else
    echo -e "${YELLOW}[!] Skipping source sync as requested.${NC}"
fi

# --- STEP 1: CLEANUP (If requested) ---
if [ "$CLEAN_FLAG" = true ]; then
    echo -e "${YELLOW}[!] Cleaning build artifacts (out/ directory)...${NC}"
    rm -rf "$BUILD_DIR/out"
fi


# --- STEP 2: FIXED BULK RESCUE ---
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

