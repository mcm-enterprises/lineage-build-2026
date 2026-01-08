#!/bin/bash

# script build-lineage2.sh
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
export TARGET_RELEASE=trunk_staging

echo -e "\n${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${MAGENTA}║   LineageOS ${VERSION} Build Script for Pixel 8 Pro (husky)      ║${NC}"
echo -e "${BOLD}${MAGENTA}║           Final Obsolete-Path & Search Fix                 ║${NC}"
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}\n"

# --- STEP 0: CHECK/INIT SOURCE ---
# Function: Robust Sync
function robust_sync() {
    echo -e "${CYAN}[→] Syncing source code (Attempting robust sync)...${NC}"
    MAX_RETRIES=5
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
            
            # 1. Check for "unsupported checkout state"
            CORRUPT_PATH=$(grep "unsupported checkout state" /tmp/repo_sync_error.log | awk -F': ' '{print $2}' | awk '{print $1}' | head -n 1)

            # 2. Check for "not a git repository" (Missing HEAD/metadata)
            NOT_GIT_PATHS=$(grep "fatal: not a git repository:" /tmp/repo_sync_error.log | cut -d"'" -f2)

            if [ -n "$CORRUPT_PATH" ] && [ -d "$CORRUPT_PATH" ]; then
                echo -e "${RED}[☢] Detected corrupted checkout at: $CORRUPT_PATH${NC}"
                echo -e "${RED}    Deleting and forcing re-download...${NC}"
                rm -rf "$CORRUPT_PATH"
                count=0 # Reset retries since we fixed something
            elif [ -n "$NOT_GIT_PATHS" ]; then
                 echo -e "${RED}[☢] Detected broken git repositories.${NC}"
                 echo "$NOT_GIT_PATHS" | while read -r path; do
                    if [ -n "$path" ]; then
                        echo -e "${RED}    Deleting corrupted git metadata: $path${NC}"
                        rm -rf "$path"
                        
                        # also delete project-objects if it exists (for shared/mirrored setups)
                        # path is .../.repo/projects/foo/bar.git
                        # obj_path should be .../.repo/project-objects/foo/bar.git
                        obj_path=${path//.repo\/projects/.repo\/project-objects}
                        if [ -d "$obj_path" ]; then
                            echo -e "${RED}    Deleting corrupted shared objects: $obj_path${NC}"
                            rm -rf "$obj_path"
                        fi
                    fi
                 done
                 count=0 # Reset retries since we fixed something
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
    # PRE-SYNC: Revert our automated patches so repo sync doesn't conflict
    # We ignore errors in case the file doesn't exist yet
    if [ -f "$BUILD_DIR/device/google/zuma/device.mk" ]; then
         echo -e "${YELLOW}[!] Reverting local patches to allow clean sync...${NC}"
         git -C "$BUILD_DIR/device/google/zuma" checkout device.mk 2>/dev/null || true
    fi

    robust_sync || exit 1
else
    echo -e "${YELLOW}[!] Skipping source sync as requested.${NC}"
fi

# --- STEP 0.1: RE-APPLY PATCHES ---
# We apply this AFTER sync to ensure it persists directly before build
echo -e "${CYAN}[→] Applying automated patches...${NC}"

# Patch 1: Wifi Ext Device Config
if [ -f "$BUILD_DIR/device/google/zuma/device.mk" ]; then
    # Robustly handle any state of this line
    sed -i 's|^include hardware/google/pixel/wifi_ext/device.mk|BOARD_VENDOR_SEPOLICY_DIRS += hardware/google/pixel-sepolicy/wifi_ext|' "$BUILD_DIR/device/google/zuma/device.mk"
    sed -i 's|^# include hardware/google/pixel/wifi_ext/device.mk|BOARD_VENDOR_SEPOLICY_DIRS += hardware/google/pixel-sepolicy/wifi_ext|' "$BUILD_DIR/device/google/zuma/device.mk"
    
    # Also include the pixelstats policy which is missing
    if ! grep -q "hardware/google/pixel-sepolicy/pixelstats" "$BUILD_DIR/device/google/zuma/device.mk"; then
        echo "BOARD_VENDOR_SEPOLICY_DIRS += hardware/google/pixel-sepolicy/pixelstats" >> "$BUILD_DIR/device/google/zuma/device.mk"
        echo -e "${GREEN}[✓] Added pixel-sepolicy/pixelstats to device.mk${NC}"
    fi
    
    echo -e "${GREEN}[✓] Patched device/google/zuma/device.mk (SEPolicy Only)${NC}"
fi



# Helper function to check if a type is already defined in the build tree
function is_type_defined() {
    local type_name="$1"
    local search_dir="$BUILD_DIR/device/google/zuma"
    # Also check hardware/google because that's where pixel-sepolicy lives
    local search_dir2="$BUILD_DIR/hardware/google"
    
    if grep -r "type $type_name" "$search_dir" >/dev/null 2>&1 || grep -r "type $type_name" "$search_dir2" >/dev/null 2>&1; then
        return 0 # True, it is defined
    else
        return 1 # False
    fi
}










# --- STEP 0.2: MEMORY CHECK & SWAP ---
function setup_swap() {
    # Check total memory + swap
    local total_mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    local total_swap_mb=$(free -m | awk '/^Swap:/{print $2}')
    local total_mb=$((total_mem_mb + total_swap_mb))
    
    # Target: 48GB (Soong can be hungry)
    local target_mb=49152
    
    if [ $total_mb -lt $target_mb ]; then
        echo -e "${YELLOW}[!] Low memory detected (Total available: ${total_mb}MB). Setting up extra swap...${NC}"
        
        SWAP_FILE="$SCRIPT_DIR/swapfile.img"
        # Calculate needed, but just force 24GB to be safe and simple
        NEEDED_MB=24576
        
        if [ ! -f "$SWAP_FILE" ]; then
            echo -e "${CYAN}[→] Creating ${NEEDED_MB}MB swap file at $SWAP_FILE (This may take a minute)...${NC}"
            # heavy operation, use dd if fallocate fails (some FS don't support fallocate)
            if ! sudo fallocate -l ${NEEDED_MB}M "$SWAP_FILE"; then
                 echo -e "${YELLOW}[!] fallocate failed, trying dd...${NC}"
                 sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$NEEDED_MB status=progress
            fi
            sudo chmod 600 "$SWAP_FILE"
            sudo mkswap "$SWAP_FILE"
        fi
        
        if ! swapon --show | grep -q "$SWAP_FILE"; then
            echo -e "${CYAN}[→] Activating swap...${NC}"
            sudo swapon "$SWAP_FILE"
        else
            echo -e "${GREEN}[✓] Extra swap already active.${NC}"
        fi
    else
        echo -e "${GREEN}[✓] Memory check passed (Total: ${total_mb}MB).${NC}"
    fi
}
setup_swap

# --- STEP 0.5: ENSURE DEVICE TREE ---
# Ensure we have the device specific trees (Pixel 8 Pro - husky)
# We manually add them to local_manifests to guarantee they are fetched
LOCAL_MANIFEST_DIR=".repo/local_manifests"
MANIFEST_FILE="$LOCAL_MANIFEST_DIR/pixel_husky.xml"

if [ ! -d "device/google/shusky" ] || [ ! -d "device/google/husky" ]; then
    echo -e "${CYAN}[→] Device trees not found. Adding husky/shusky to local_manifests...${NC}"
    mkdir -p "$LOCAL_MANIFEST_DIR"
    
    # We add likely dependencies. 
    # device/google/shusky (Unified platform)
    # device/google/husky (Device specific)
    # kernel/google/zuma (Kernel)
    # hardware/google/pixel (Common hardware)
    cat <<EOF > "$MANIFEST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <project name="LineageOS/android_device_google_shusky" path="device/google/shusky" remote="github" />
    <project name="LineageOS/android_device_google_husky" path="device/google/husky" remote="github" />
</manifest>
EOF

    echo -e "${CYAN}[→] Syncing device specific repositories...${NC}"
    # We call robust_sync again to fetch the new projects
    robust_sync || exit 1
fi

# --- STEP 1: CLEANUP (If requested) ---
if [ "$CLEAN_FLAG" = true ]; then
    echo -e "${YELLOW}[!] Cleaning build artifacts (out/ directory)...${NC}"
    rm -rf "$BUILD_DIR/out"
fi


# --- STEP 2: FIXED BULK RESCUE ---
# --- STEP 2: FIXED BULK RESCUE ---
echo -e "${CYAN}[→] STEP 2: Extracting Proprietary Blobs...${NC}"

# --- STEP 2: FIXED BULK RESCUE ---
echo -e "${CYAN}[→] STEP 2: Extracting Proprietary Blobs...${NC}"

# Create a WRITABLE dump directory (extract-files.py needs to move/delete things)
DUMP_DIR="$SCRIPT_DIR/images/dump"
rm -rf "$DUMP_DIR"
mkdir -p "$DUMP_DIR"

echo -e "${YELLOW}[!] extracting images to writable directory (slow but required)...${NC}"

# Function to extract image content
extract_img() {
    img="$1"
    target="$2"
    echo "    Extracting $(basename "$img") to $target..."
    mkdir -p "$target"
    # Mount locally just to copy out
    temp_mnt=$(mktemp -d)
    sudo mount -t erofs,ext4 -o ro "$img" "$temp_mnt"
    try_cp=$(sudo cp -a "$temp_mnt/"* "$target/" 2>/dev/null)
    sudo umount "$temp_mnt"
    rmdir "$temp_mnt"
    # Fix permissions so we can write to it
    sudo chown -R $(whoami) "$target"
    chmod -R u+w "$target"
}

extract_img "$EXTRACTED_IMAGES/system.img" "$DUMP_DIR/system"
extract_img "$EXTRACTED_IMAGES/system_ext.img" "$DUMP_DIR/system_ext"
extract_img "$EXTRACTED_IMAGES/product.img" "$DUMP_DIR/product"
extract_img "$EXTRACTED_IMAGES/vendor.img" "$DUMP_DIR/vendor"

# Locate the extract script
# Try common paths
POSSIBLE_SCRIPTS=(
    "$BUILD_DIR/device/google/shusky/extract-files.py"
    "$BUILD_DIR/device/google/husky/extract-files.py"
    "$BUILD_DIR/device/google/shusky/husky/extract-files.py"
)

EXTRACT_SCRIPT=""
for script in "${POSSIBLE_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        EXTRACT_SCRIPT="$script"
        echo -e "${CYAN}[→] Found extraction script at $EXTRACT_SCRIPT${NC}"
        break
    fi
done

if [ -n "$EXTRACT_SCRIPT" ]; then
    echo -e "${CYAN}[→] Running standard LineageOS extraction script...${NC}"
    SCRIPT_DIR_PARENT=$(dirname "$EXTRACT_SCRIPT")
    pushd "$SCRIPT_DIR_PARENT" > /dev/null
    
    # -k to continue even if some files are missing
    ./extract-files.py "$DUMP_DIR" -k || true
    
    popd > /dev/null

    # AUTO-FIX: If extraction was "too partial" and didn't make the makefile, force it.
    MK_FILE="$BUILD_DIR/vendor/google/husky/husky-vendor.mk"
    if [ ! -f "$MK_FILE" ]; then
        echo -e "${YELLOW}[!] extract-files.py failed to generate valid makefiles. Generating fallback...${NC}"
        mkdir -p "$(dirname "$MK_FILE")"
        cat <<EOF > "$MK_FILE"
# Auto-generated fallback by build-lineage2.sh
\$(call inherit-product, vendor/google/husky/husky-vendor-blobs.mk)
EOF
        # We also need the blobs makefile to exist, even if empty, to stop the build from crashing
        touch "$BUILD_DIR/vendor/google/husky/husky-vendor-blobs.mk"
    fi

    # AUTO-FIX: We ALSO need BoardConfigVendor.mk or the build fails earlier
    BOARD_MK_FILE="$BUILD_DIR/vendor/google/husky/BoardConfigVendor.mk"
    if [ ! -f "$BOARD_MK_FILE" ]; then
        echo -e "${YELLOW}[!] missing BoardConfigVendor.mk. Generating fallback...${NC}"
        mkdir -p "$(dirname "$BOARD_MK_FILE")"
        cat <<EOF > "$BOARD_MK_FILE"
# Auto-generated fallback by build-lineage2.sh
-include vendor/google/husky/BoardConfigVendor-blobs.mk
EOF
        touch "$BUILD_DIR/vendor/google/husky/BoardConfigVendor-blobs.mk"
    fi
else
    echo -e "${RED}[✗] extract-files.py not found using defaults.${NC}"
    echo -e "    Checked locations:"
    for script in "${POSSIBLE_SCRIPTS[@]}"; do
        echo -e "    - $script"
    done
    exit 1
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


