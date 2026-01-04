#!/bin/bash

# LineageOS 22.1 Build Script for Pixel 8 Pro (husky)
# Optimized for Ubuntu 25.10 & No-Device Blob Extraction

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

# Step counter
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
    print_substep "Killing any previous build processes..."
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
    
    # Path Detection for Husky
    local device_path="$BUILD_DIR/device/google/husky"
    if [ ! -d "$device_path" ]; then
        print_warning "Device tree not found at $device_path, attempting breakfast to pull it..."
        cd "$BUILD_DIR"
        source build/envsetup.sh
        breakfast "$DEVICE"
    fi

    if [ -f "$device_path/extract-files.sh" ]; then
        cd "$device_path"
    elif [ -f "$BUILD_DIR/device/google/shusky/extract-files.sh" ]; then
        cd "$BUILD_DIR/device/google/shusky"
    else
        print_error "extract-files.sh not found in device/google/husky or shusky."
        return 1
    fi

    chmod +x extract-files.sh
    print_substep "Running extraction script using local images..."
    ./extract-files.sh "$extract_dir"
}

# --- SCRIPT START ---

print_step "CLEANUP & PREPARATION"
STEP_START=$(date +%s)
kill_previous_instances
remove_lock_files
show_elapsed_time $STEP_START

print_step "INSTALL BUILD DEPENDENCIES"
sudo apt-get update
sudo apt-get install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev liblz4-tool libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync squashfs-tools xsltproc zip zlib1g-dev openjdk-17-jdk python3 python-is-python3 adb fastboot wget unzip
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true

print_step "INITIALIZE LINEAGEOS REPOSITORY"
mkdir -p "$BUILD_DIR" "$ZIPS_DIR" "$LOG_DIR" "$MANIFEST_DIR" "$FACTORY_IMAGE_DIR"
cd "$BUILD_DIR" || exit 1
if [ "$SKIP_SYNC" = false ]; then
    [ ! -d ".repo" ] && repo init -u "$REPO_URL" -b "$LINEAGE_VERSION" --git-lfs
fi

print_step "DOWNLOAD LINEAGEOS SOURCE CODE"
if [ "$SKIP_SYNC" = true ]; then
    print_warning "Skipping repo sync."
else
    repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags
fi

print_step "DOWNLOAD & EXTRACT PROPRIETARY BLOBS"
BLOB_CHECK="$BUILD_DIR/vendor/google/husky/proprietary/product/etc/CarrierSettings/reachmobileatt_us.pb"

if [ -f "$BLOB_CHECK" ] && [ "$FORCE_BLOBS" = false ]; then
    print_status "Blobs verified in vendor folder. Skipping extraction."
else
    print_warning "Blobs missing or extraction forced. Starting..."
    FACTORY_PATH=$(download_factory_image)
    extract_proprietary_blobs "$FACTORY_PATH"
    
    # Final Verification
    if [ ! -f "$BLOB_CHECK" ]; then
        print_error "Extraction FAILED: $BLOB_CHECK not found."
        exit 1
    fi
fi
cd "$BUILD_DIR" || exit 1

print_step "CONFIGURE CCACHE"
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G

print_step "PREPARE DEVICE-SPECIFIC CODE"
mkdir -p "$BUILD_DIR/external/iptables/iptables"
touch "$BUILD_DIR/external/iptables/iptables/xtables.lock"

source build/envsetup.sh
breakfast "$DEVICE"

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

[ "$build_success" = false ] && { print_error "Build failed after retries."; exit 1; }

print_step "BUILD COMPLETE - SUMMARY"
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║              BUILD COMPLETED SUCCESSFULLY!                 ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
print_info "Output folder: $ZIPS_DIR"