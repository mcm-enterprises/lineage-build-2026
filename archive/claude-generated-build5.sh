#!/bin/bash

# LineageOS 22.1 Build Script for Pixel 8 Pro (husky)
# For Ubuntu 25.10 - Optimized for No-Device Extraction
# Full Version with Dependency Logic and Ubuntu Patches

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Parse command line arguments
SKIP_SYNC=false
FORCE_BLOBS=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-sync    Skip repo sync step (use if code already downloaded)"
    echo "  --force-blobs  Force re-extraction of blobs even if vendor folder exists"
    echo "  -h, --help     Show this help message"
    echo ""
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-sync) SKIP_SYNC=true; shift ;;
        --force-blobs) FORCE_BLOBS=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Configuration
DEVICE="husky"
LINEAGE_VERSION="lineage-22.1"
SCRIPT_DIR="$(pwd)"
SRC_NAME="android_source/LINEAGE_22_1"
BUILD_DIR="$SCRIPT_DIR/$SRC_NAME"
REPO_URL="https://github.com/LineageOS/android.git"
MAX_RETRIES=5
JOBS=$(nproc --all)
FACTORY_IMAGE_DIR="$SCRIPT_DIR/images"
FACTORY_IMAGE_URL="https://dl.google.com/dl/android/aosp"
ZIPS_DIR="$SCRIPT_DIR/zips"
LOG_DIR="$SCRIPT_DIR/logs"
MANIFEST_DIR="$SCRIPT_DIR/local_manifests"

# --- MANDATORY UBUNTU 25.10 DATE WRAPPER ---
# Fixes 'invalid date TZ="GMT"' by intercepting the call globally
date() {
  if [[ "$*" == *"TZ=\"GMT\""* ]]; then
    local clean_args=$(echo "$*" | sed 's/TZ="GMT"//g')
    command date $clean_args
  else
    command date "$@"
  fi
}
export -f date

# --- GLOBAL UBUNTU 25.10 WORKAROUNDS ---
export LC_ALL=C
export OVERRIDE_BUILD_DATE=$(date +%s)
export BUILD_DATETIME_CHECK=false
export PATH=$PATH:/usr/lib/android-sdk/platform-tools:$HOME/.bin

# Step counter initialization
CURRENT_STEP=0
TOTAL_STEPS=13

# --- UI Functions ---
print_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo -e "${BOLD}${CYAN}STEP $CURRENT_STEP/$TOTAL_STEPS: $1${NC}"
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo ""
}

print_substep() { echo -e "${BLUE}  ► $1${NC}"; }
print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${MAGENTA}[ℹ]${NC} $1"; }
print_progress() { echo -e "${CYAN}[→]${NC} $1"; }

show_elapsed_time() {
    local start_time=$1
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))
    local seconds=$((elapsed % 60))
    echo -e "${GREEN}[✓] Time elapsed: ${hours}h ${minutes}m ${seconds}s${NC}"
}

# --- Helper Functions ---
kill_previous_instances() {
    print_substep "Killing previous build processes..."
    pkill -f "build_lineage.sh" || true
    pkill -f "repo sync" || true
    pkill -f "brunch" || true
    sleep 2
}

remove_lock_files() {
    if [ -d "$BUILD_DIR" ]; then
        find "$BUILD_DIR" -name "*.lock" -type f -delete 2>/dev/null || true
        find "$BUILD_DIR/.repo" -name "*.lock" -type f -delete 2>/dev/null || true
    fi
}

get_latest_factory_image() {
    local temp_page="/tmp/factory_images.html"
    curl -s "https://developers.google.com/android/images" -o "$temp_page"
    local latest_image=$(grep -o "husky-[a-z0-9.-]*-factory-[a-z0-9]*.zip" "$temp_page" | head -1)
    echo "$latest_image"
}

download_factory_image() {
    mkdir -p "$FACTORY_IMAGE_DIR"
    cd "$FACTORY_IMAGE_DIR" || exit 1
    local existing_image=$(ls husky-*-factory-*.zip 2>/dev/null | head -1)
    if [ -n "$existing_image" ] && unzip -t "$existing_image" &>/dev/null; then
        echo "$FACTORY_IMAGE_DIR/$existing_image"
        return 0
    fi
    local image_name=$(get_latest_factory_image)
    [ -z "$image_name" ] && image_name="husky-ap4a.250205.002.b2-factory-81c3d0c5.zip"
    wget -c "$FACTORY_IMAGE_URL/$image_name"
    echo "$FACTORY_IMAGE_DIR/$image_name"
}

extract_proprietary_blobs() {
    local factory_zip="$1"
    local extract_dir="$FACTORY_IMAGE_DIR/extracted"
    rm -rf "$extract_dir" && mkdir -p "$extract_dir"
    
    print_progress "Unpacking primary factory zip..."
    unzip -q -o "$factory_zip" -d "$extract_dir"
    
    local inner_zip=$(find "$extract_dir" -name "image-*.zip" | head -1)
    print_progress "Unpacking partition images (system, vendor, product)..."
    unzip -q -o "$inner_zip" -d "$extract_dir"
    
    # Check if device tree exists, if not, pull it
    if [ ! -d "$BUILD_DIR/device/google/husky" ]; then
        print_warning "Device tree missing. Sourcing env and running breakfast..."
        cd "$BUILD_DIR"
        source build/envsetup.sh
        breakfast "$DEVICE" || true
    fi

    # Locate extraction script
    local script_path=""
    if [ -f "$BUILD_DIR/device/google/husky/extract-files.sh" ]; then
        script_path="$BUILD_DIR/device/google/husky"
    elif [ -f "$BUILD_DIR/device/google/shusky/extract-files.sh" ]; then
        script_path="$BUILD_DIR/device/google/shusky"
    fi

    if [ -n "$script_path" ]; then
        cd "$script_path"
        chmod +x extract-files.sh
        ./extract-files.sh "$extract_dir"
    else
        print_error "extract-files.sh not found. Ensure repo sync finished correctly."
        return 1
    fi
}

# --- SCRIPT START ---

echo -e "\n${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${MAGENTA}║   LineageOS 22.1 Build Script for Pixel 8 Pro (husky)     ║${NC}"
echo -e "${BOLD}${MAGENTA}║                   Ubuntu 25.10                             ║${NC}"
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}\n"

# Step 1: Preparation
print_step "CLEANUP & PREPARATION"
kill_previous_instances
remove_lock_files

# Step 2: System Dependencies
print_step "INSTALL BUILD DEPENDENCIES"
sudo apt-get update
sudo apt-get install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev liblz4-tool libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync squashfs-tools xsltproc zip zlib1g-dev openjdk-17-jdk python3 python-is-python3 adb fastboot wget unzip
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true

# Step 3: Directories
print_step "CREATE BUILD DIRECTORY"
mkdir -p "$BUILD_DIR" "$ZIPS_DIR" "$LOG_DIR" "$MANIFEST_DIR" "$FACTORY_IMAGE_DIR"
cd "$BUILD_DIR" || exit 1

# Step 4: Initialize
print_step "INITIALIZE LINEAGEOS REPOSITORY"
if [ "$SKIP_SYNC" = false ]; then
    [ ! -d ".repo" ] && repo init -u "$REPO_URL" -b "$LINEAGE_VERSION" --git-lfs
fi

# Step 5: Sync
print_step "DOWNLOAD LINEAGEOS SOURCE CODE"
if [ "$SKIP_SYNC" = true ]; then
    print_warning "Skipping repo sync."
else
    repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags
fi

# Step 6: Blobs
print_step "DOWNLOAD & EXTRACT PROPRIETARY BLOBS"
BLOB_SENTINEL="$BUILD_DIR/vendor/google/husky/proprietary/product/etc/CarrierSettings/reachmobileatt_us.pb"

if [ -f "$BLOB_SENTINEL" ] && [ "$FORCE_BLOBS" = false ]; then
    print_status "Blobs verified. Skipping extraction."
else
    FACTORY_PATH=$(download_factory_image)
    extract_proprietary_blobs "$FACTORY_PATH"
    if [ ! -f "$BLOB_SENTINEL" ]; then
        print_error "Extraction FAILED: Sentinel file missing."
        exit 1
    fi
fi
cd "$BUILD_DIR" || exit 1

# Step 7: Ccache
print_step "CONFIGURE CCACHE"
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G

# Step 8: Breakfast & Patches
print_step "PREPARE DEVICE-SPECIFIC CODE"
# Fix xtables.lock error (Ubuntu 25.10 specific)
mkdir -p "$BUILD_DIR/external/iptables/iptables"
touch "$BUILD_DIR/external/iptables/iptables/xtables.lock"

source build/envsetup.sh
breakfast "$DEVICE"

# Step 9: Build
print_step "BUILD LINEAGEOS"
BUILD_START=$(date +%s)
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true
build_success=false
build_attempt=1

while [ $build_attempt -le $MAX_RETRIES ] && [ "$build_success" = false ]; do
    print_substep "Build attempt $build_attempt of $MAX_RETRIES"
    touch "$BUILD_DIR/external/iptables/iptables/xtables.lock"
    
    if m -j"$JOBS" bacon; then
        build_success=true
        print_status "Build Success!"
        mv out/target/product/"$DEVICE"/lineage-*.zip "$ZIPS_DIR/" 2>/dev/null
    else
        ((build_attempt++))
        [ $build_attempt -le $MAX_RETRIES ] && make installclean
    fi
done

# Step 10: Summary
print_step "BUILD COMPLETE - SUMMARY"
if [ "$build_success" = true ]; then
    echo -e "\n${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║              BUILD COMPLETED SUCCESSFULLY!                 ║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}\n"
    print_info "Output folder: $ZIPS_DIR"
    ls -lh "$ZIPS_DIR"
else
    print_error "Build failed after $MAX_RETRIES attempts."
fi