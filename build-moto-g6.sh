#!/bin/bash

# script build-moto-g6.sh
# LineageOS Build Script for Moto G6 (ali) - Mission Impossible Edition
# Architecturally aligned with build-lineage2.sh

# --- COLORS ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
CYAN='\033[0;36m'; MAGENTA='\033[1;35m'; BOLD='\033[1m'; NC='\033[0m'

# --- CONFIG ---
# Default to 23.1 because we are sharing the source tree with Husky
VERSION="23.1"
SKIP_SYNC=false
CLEAN_FLAG=false
DEVICE_CODENAME="ali"

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

# Convert dots to underscores for directory naming (e.g. 23.1 -> 23_1)
VERSION_DIR_SUFFIX=${VERSION//./_}

# We reuse the main Android source tree
SRC_NAME="android_source/LINEAGE_${VERSION_DIR_SUFFIX}"

# Automatically detect the script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/$SRC_NAME"
ZIPS_DIR="$SCRIPT_DIR/zips"
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
export TARGET_RELEASE=trunk_staging

echo -e "\n${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${MAGENTA}║   LineageOS ${VERSION} Build Script for Moto G6 (ali)          ║${NC}"
echo -e "${BOLD}${MAGENTA}║           Mission Impossible Edition                       ║${NC}"
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}\n"

# --- STEP 0: CHECK/INIT SOURCE ---
# Function: Robust Sync
function robust_sync() {
    echo -e "${CYAN}[→] Syncing source code (Attempting robust sync)...${NC}"
    MAX_RETRIES=5
    count=0
    
    while [ $count -lt $MAX_RETRIES ]; do
        # We capture both stdout and stderr (but we can't use tee easily with variables without pipefail)
        # Using the same robust definition as build-lineage2.sh
        if repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags --verbose 2> >(tee /tmp/repo_sync_error.log >&2); then
            echo -e "${GREEN}[✓] Sync completed successfully.${NC}"
            return 0
        else
            current_attempt=$((count + 1))
            echo -e "${YELLOW}[!] Sync failed (Attempt $current_attempt/$MAX_RETRIES). Checking for corruption...${NC}"
            
            # 1. Check for "unsupported checkout state"
            CORRUPT_PATH=$(grep "unsupported checkout state" /tmp/repo_sync_error.log | awk -F': ' '{print $2}' | awk '{print $1}' | head -n 1)

            # 2. Check for "not a git repository"
            NOT_GIT_PATHS=$(grep "fatal: not a git repository:" /tmp/repo_sync_error.log | cut -d"'" -f2)

            if [ -n "$CORRUPT_PATH" ] && [ -d "$CORRUPT_PATH" ]; then
                echo -e "${RED}[☢] Detected corrupted checkout at: $CORRUPT_PATH${NC}"
                rm -rf "$CORRUPT_PATH"
                count=0 
            elif [ -n "$NOT_GIT_PATHS" ]; then
                 echo -e "${RED}[☢] Detected broken git repositories.${NC}"
                 echo "$NOT_GIT_PATHS" | while read -r path; do
                    if [ -n "$path" ]; then
                        echo -e "${RED}    Deleting corrupted git metadata: $path${NC}"
                        rm -rf "$path"
                        obj_path=${path//.repo\/projects/.repo\/project-objects}
                        if [ -d "$obj_path" ]; then rm -rf "$obj_path"; fi
                    fi
                 done
                 count=0
            else
                echo -e "${YELLOW}[?] No auto-fixable corruption detected. Retrying standard sync...${NC}"
                find .repo -name "*.lock" -delete 2>/dev/null
            fi
            
            count=$((count + 1))
            sleep 5
        fi
    done
    
    echo -e "${RED}[✗] Sync failed after multiple attempts.${NC}"
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

# --- STEP 0.5: MANIFEST MANAGEMENT ---
# Always enforce central manifests
LOCAL_MANIFEST_DIR=".repo/local_manifests"
mkdir -p "$LOCAL_MANIFEST_DIR"

if [ -d "$SCRIPT_DIR/manifests" ]; then
    echo -e "${CYAN}[→] Copying manifests from $SCRIPT_DIR/manifests to .repo/local_manifests...${NC}"
    cp "$SCRIPT_DIR/manifests/"*.xml "$LOCAL_MANIFEST_DIR/" 2>/dev/null || true
else
    echo -e "${YELLOW}[!] no 'manifests' directory found in project root.${NC}"
fi

# Run Sync (Unless skipped)
if [ "$SKIP_SYNC" = false ]; then
    # We only sync specific projects for safety if we think the whole tree is too big?
    # No, build-lineage2.sh syncs everything. We shall do the same to ensure consistency.
    robust_sync || exit 1
else
    echo -e "${YELLOW}[!] Skipping source sync as requested.${NC}"
fi

# --- STEP 0.1: RE-APPLY PATCHES (Moto Specific) ---
echo -e "${CYAN}[→] Applying Moto G6 'Mission Impossible' patches...${NC}"

# Patch: Rename CrDroid makefile to Lineage if needed
MK_FILE="device/motorola/ali/lineage_ali.mk"
CR_FILE="device/motorola/ali/crdroid_ali.mk"

if [ ! -f "$MK_FILE" ] && [ -f "$CR_FILE" ]; then
    echo -e "${YELLOW}[!] Converting CrDroid makefile to Lineage...${NC}"
    mv "$CR_FILE" "$MK_FILE"
    sed -i 's/crdroid/lineage/g' "$MK_FILE"
    sed -i 's/vendor\/crdroid/vendor\/lineage/g' "$MK_FILE"
    echo -e "${GREEN}[✓] Created lineage_ali.mk${NC}"
fi

# Patch inheritance
if [ -f "$MK_FILE" ]; then
    if grep -q "vendor/crdroid/config/common.mk" "$MK_FILE"; then
        sed -i 's|vendor/crdroid/config/common.mk|vendor/lineage/config/common.mk|g' "$MK_FILE"
        echo -e "${GREEN}[✓] Patched inheritance in lineage_ali.mk${NC}"
    fi
fi

# --- STEP 0.2: MEMORY CHECK & SWAP ---
function setup_swap() {
    local total_mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    local total_swap_mb=$(free -m | awk '/^Swap:/{print $2}')
    local total_mb=$((total_mem_mb + total_swap_mb))
    local target_mb=49152
    
    if [ $total_mb -lt $target_mb ]; then
        echo -e "${YELLOW}[!] Low memory detected. Checking swap...${NC}"
        SWAP_FILE="$SCRIPT_DIR/swapfile.img"
        NEEDED_MB=24576
        
        if [ ! -f "$SWAP_FILE" ]; then
            echo -e "${CYAN}[→] Creating ${NEEDED_MB}MB swap file...${NC}"
            if ! sudo fallocate -l ${NEEDED_MB}M "$SWAP_FILE"; then
                 sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$NEEDED_MB status=progress
            fi
            sudo chmod 600 "$SWAP_FILE"
            sudo mkswap "$SWAP_FILE"
        fi
        
        if ! swapon --show | grep -q "$SWAP_FILE"; then
            sudo swapon "$SWAP_FILE"
        fi
    fi
}
setup_swap

# --- STEP 1: CLEANUP (If requested) ---
if [ "$CLEAN_FLAG" = true ]; then
    echo -e "${YELLOW}[!] Cleaning build artifacts (out/ directory)...${NC}"
    rm -rf "$BUILD_DIR/out"
fi

# --- STEP 2: BLOBS ---
# Only minimal check for Moto G6, since we use vendor tree from git
echo -e "${CYAN}[→] STEP 2: Blobs (Skipping extraction, assuming Git vendor tree)...${NC}"
if [ ! -d "vendor/motorola/ali" ]; then
    echo -e "${RED}[!] WARNING: vendor/motorola/ali not found. Did the manifest sync work?${NC}"
    # proceed anyway, maybe it will fail later
fi

# --- STEP 2: BUILD CONFIG ---
echo -e "\n${CYAN}[→] STEP 2: Initializing Build Environment...${NC}"

# Unset ccache to be safe / match other script
unset USE_CCACHE
unset CCACHE_DIR
unset CCACHE_EXEC
unset CC_WRAPPER
unset TEMPORARY_DISABLE_PATH_RESTRICTIONS

source build/envsetup.sh

# --- STEP 3: LAUNCH ---
echo -e "\n${CYAN}[→] STEP 3: Starting Ninja build...${NC}"

# We try standard breakfast first, fallback to manual lunch
if check_product "lineage_$DEVICE_CODENAME"; then
    echo -e "${CYAN}[→] Found official/standard product definition.${NC}"
    breakfast "lineage_$DEVICE_CODENAME"
else
    echo -e "${YELLOW}[!] Standard 'breakfast' lookup failed. Attempting manual lunch...${NC}"
    # Special "Mission Impossible" Lunch logic
    export LINEAGE_BUILDTYPE=UNOFFICIAL
    if lunch "lineage_${DEVICE_CODENAME}-userdebug"; then
        echo -e "${GREEN}[✓] Lunch successful.${NC}"
    elif lunch "lineage_${DEVICE_CODENAME}-eng"; then
        echo -e "${GREEN}[✓] Lunch (eng) successul.${NC}"
    else
        echo -e "${RED}[✗] Lunch failed. Check lineage_ali.mk and AndroidProducts.mk${NC}"
        exit 1
    fi
fi

if m bacon -j"$JOBS"; then
    echo -e "\n${BOLD}${GREEN}SUCCESS! BUILD COMPLETED.${NC}"
    echo -e "${BOLD}Your flashable zip is here:${NC}"
    ls -lh out/target/product/$DEVICE_CODENAME/lineage-*.zip

    # Copy to top-level zips directory
    mkdir -p "$ZIPS_DIR"
    echo -e "${CYAN}[→] Copying build artifacts to $ZIPS_DIR...${NC}"
    cp out/target/product/$DEVICE_CODENAME/lineage-*.zip "$ZIPS_DIR/" && echo -e "${GREEN}[✓] Artifacts securely backed up to $ZIPS_DIR${NC}"
else
    echo -e "\n${RED}[✗] Build failed.${NC}"
    exit 1
fi
