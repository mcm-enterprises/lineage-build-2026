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
EXTRACT_SCRIPT="$BUILD_DIR/device/google/shusky/husky/extract-files.py"

if [ -f "$EXTRACT_SCRIPT" ]; then
    echo -e "${CYAN}[→] Running standard LineageOS extraction script...${NC}"
    pushd "$BUILD_DIR/device/google/shusky/husky" > /dev/null
    
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
    echo -e "${RED}[✗] extract-files.py not found at $EXTRACT_SCRIPT${NC}"
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


