#!/bin/bash

# LineageOS 22.1 Build Script for Pixel 8 Pro (husky)
# For Ubuntu 25.10 - Optimized for No-Device Extraction

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
        --skip-sync)
            SKIP_SYNC=true
            shift
            ;;
        --force-blobs)
            FORCE_BLOBS=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
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
# This fixes the 'invalid date TZ="GMT"' error by intercepting the call globally
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
# Ensure tools are in PATH
export PATH=$PATH:/usr/lib/android-sdk/platform-tools:$HOME/.bin
# ---------------------------------------

# Step counter
CURRENT_STEP=0
TOTAL_STEPS=12
if [ "$SKIP_SYNC" = true ]; then
    TOTAL_STEPS=10
fi

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
    print_status "Process cleanup complete"
}

remove_lock_files() {
    print_substep "Scanning for .lock files..."
    if [ -d "$BUILD_DIR" ]; then
        local lock_count
        lock_count=$(find "$BUILD_DIR" -name "*.lock" -type f 2>/dev/null | wc -l)
        if [ "$lock_count" -gt 0 ]; then
            print_progress "Found $lock_count lock files, removing..."
            find "$BUILD_DIR" -name "*.lock" -type f -delete 2>/dev/null || true
            find "$BUILD_DIR/.repo" -name "*.lock" -type f -delete 2>/dev/null || true
            print_status "Removed $lock_count lock files"
        else
            print_status "No lock files found"
        fi
    fi
}

get_latest_factory_image() {
    print_substep "Fetching latest factory image information..."
    local temp_page="/tmp/factory_images.html"
    curl -s "https://developers.google.com/android/images" -o "$temp_page"
    local latest_image=$(grep -o "husky-[a-z0-9.-]*-factory-[a-z0-9]*.zip" "$temp_page" | head -1)
    if [ -z "$latest_image" ]; then
        print_warning "Could not auto-detect latest image"
        return 1
    fi
    echo "$latest_image"
}

download_factory_image() {
    print_substep "Checking factory image status..."
    mkdir -p "$FACTORY_IMAGE_DIR"
    cd "$FACTORY_IMAGE_DIR" || exit 1
    
    local existing_image=$(ls husky-*-factory-*.zip 2>/dev/null | head -1)
    if [ -n "$existing_image" ]; then
        print_status "Found existing factory image: $existing_image"
        if unzip -t "$existing_image" &>/dev/null; then
            print_status "Existing file is valid"
            echo "$FACTORY_IMAGE_DIR/$existing_image"
            return 0
        else
            print_warning "Existing file corrupted, removing..."
            rm -f "$existing_image"
        fi
    fi

    local image_name=$(get_latest_factory_image)
    [ -z "$image_name" ] && image_name="husky-ap4a.250205.002.b2-factory-81c3d0c5.zip"
    
    print_progress "Downloading $image_name..."
    wget -c "$FACTORY_IMAGE_URL/$image_name"
    echo "$FACTORY_IMAGE_DIR/$image_name"
}

extract_proprietary_blobs() {
    local factory_zip="$1"
    print_substep "Starting No-Device extraction process..."
    
    local extract_dir="$FACTORY_IMAGE_DIR/extracted"
    mkdir -p "$extract_dir"
    
    print_progress "Unpacking primary zip..."
    unzip -q -o "$factory_zip" -d "$extract_dir"
    
    local inner_zip=$(find "$extract_dir" -name "image-*.zip" | head -1)
    if [ -z "$inner_zip" ]; then
        print_error "Could not find nested image-*.zip"
        return 1
    fi
    
    print_progress "Unpacking nested partition images (.img files)..."
    unzip -q -o "$inner_zip" -d "$extract_dir"
    
    cd "$BUILD_DIR/device/google/$DEVICE" || return 1
    chmod +x extract-files.sh
    
    print_progress "Running LineageOS extract-files script against local images..."
    ./extract-files.sh "$extract_dir"
}

retry_command() {
    local cmd="$1"
    local max_attempts="$2"
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        print_progress "Attempt $attempt of $max_attempts"
        if eval "$cmd"; then return 0; fi
        [ $attempt -lt $max_attempts ] && sleep 10
        attempt=$((attempt + 1))
    done
    return 1
}

# --- SCRIPT START ---

echo ""
echo -e "${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${MAGENTA}║                                                            ║${NC}"
echo -e "${BOLD}${MAGENTA}║   LineageOS 22.1 Build Script for Pixel 8 Pro (husky)      ║${NC}"
echo -e "${BOLD}${MAGENTA}║                   Ubuntu 25.10                             ║${NC}"
echo -e "${BOLD}${MAGENTA}║                                                            ║${NC}"
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Cleanup
print_step "CLEANUP & PREPARATION"
STEP_START=$(date +%s)
kill_previous_instances
remove_lock_files
show_elapsed_time $STEP_START

# Step 2: Install Dependencies
print_step "INSTALL BUILD DEPENDENCIES"
STEP_START=$(date +%s)
sudo apt-get update
sudo apt-get install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev liblz4-tool libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync squashfs-tools xsltproc zip zlib1g-dev openjdk-17-jdk python3 python-is-python3 adb fastboot wget unzip
# UBUNTU 25.10 FIX: Allow nsjail (unprivileged user namespaces)
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true
show_elapsed_time $STEP_START

# Step 3: Repo tool
print_step "INSTALL REPO TOOL"
STEP_START=$(date +%s)
mkdir -p ~/.bin
PATH="${HOME}/.bin:${PATH}"
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo
chmod a+rx ~/.bin/repo
grep -q 'PATH="${HOME}/.bin:${PATH}"' ~/.bashrc || echo 'PATH="${HOME}/.bin:${PATH}"' >> ~/.bashrc
show_elapsed_time $STEP_START

# Step 4: Git Config
print_step "CONFIGURE GIT"
STEP_START=$(date +%s)
[ -z "$(git config --global user.email)" ] && { echo "Enter Git Email:"; read -r e; git config --global user.email "$e"; }
[ -z "$(git config --global user.name)" ] && { echo "Enter Git Name:"; read -r n; git config --global user.name "$n"; }
show_elapsed_time $STEP_START

# Step 5: Directory structure
print_step "CREATE BUILD DIRECTORY"
STEP_START=$(date +%s)
mkdir -p "$BUILD_DIR" "$ZIPS_DIR" "$LOG_DIR" "$MANIFEST_DIR" "$FACTORY_IMAGE_DIR"
cd "$BUILD_DIR" || exit 1
show_elapsed_time $STEP_START

# Step 6: Initialize Repo
print_step "INITIALIZE LINEAGEOS REPOSITORY"
STEP_START=$(date +%s)
if [ "$SKIP_SYNC" = false ]; then
    retry_command "repo init -u '$REPO_URL' -b '$LINEAGE_VERSION' --git-lfs" 3
fi
show_elapsed_time $STEP_START

# Step 7: Local Manifests
print_step "COPY LOCAL MANIFESTS"
STEP_START=$(date +%s)
mkdir -p .repo/local_manifests
if ls "$MANIFEST_DIR"/*.xml 1> /dev/null 2>&1; then
    cp "$MANIFEST_DIR"/*.xml .repo/local_manifests/
fi
show_elapsed_time $STEP_START

# Step 8: Source Sync
print_step "DOWNLOAD LINEAGEOS SOURCE CODE"
STEP_START=$(date +%s)
if [ "$SKIP_SYNC" = true ]; then
    print_warning "Skipping repo sync."
else
    sync_attempt=1
    while [ $sync_attempt -le $MAX_RETRIES ]; do
        remove_lock_files
        if repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags; then break; fi
        ((sync_attempt++))
        sleep 15
    done
fi
show_elapsed_time $STEP_START

# Step 9: Extract Blobs
print_step "DOWNLOAD & EXTRACT PROPRIETARY BLOBS"
STEP_START=$(date +%s)

# --- PRE-BUILD PATCH: Fix xtables.lock missing error ---
print_substep "Applying source patches for Ubuntu 25.10..."
if [ -d "$BUILD_DIR/external/iptables" ]; then
    mkdir -p "$BUILD_DIR/external/iptables/iptables"
    touch "$BUILD_DIR/external/iptables/iptables/xtables.lock"
    print_status "Created xtables.lock placeholder"
fi

VENDOR_DIR="$BUILD_DIR/vendor/google/$DEVICE"
if [ -d "$VENDOR_DIR" ] && [ "$(ls -A "$VENDOR_DIR" 2>/dev/null)" ] && [ "$FORCE_BLOBS" = false ]; then
    print_status "Proprietary blobs already exist. skipping extraction."
else
    factory_path=$(download_factory_image)
    if [ -f "$factory_path" ]; then
        if extract_proprietary_blobs "$factory_path"; then
            print_status "Blobs successfully extracted from local images!"
        else
            print_error "Extraction failed."
            exit 1
        fi
    fi
fi
cd "$BUILD_DIR" || exit 1
show_elapsed_time $STEP_START

# Step 10: Ccache
print_step "CONFIGURE CCACHE"
STEP_START=$(date +%s)
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G
show_elapsed_time $STEP_START

# Step 11: Breakfast
print_step "PREPARE DEVICE-SPECIFIC CODE"
STEP_START=$(date +%s)
# Global 'date' wrapper at the top fixes the TZ errors here
source build/envsetup.sh
print_substep "Running breakfast for device: $DEVICE"
breakfast "$DEVICE"
show_elapsed_time $STEP_START

# Step 12: Build LineageOS
print_step "BUILD LINEAGEOS"
BUILD_START=$(date +%s)

# Re-apply nsjail fix for Ubuntu 25.10 compilation phase
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true

build_success=false
build_attempt=1

while [ $build_attempt -le $MAX_RETRIES ] && [ "$build_success" = false ]; do
    print_substep "Build attempt $build_attempt of $MAX_RETRIES"
    remove_lock_files
    
    # Ensure xtables fix is present before build starts
    touch "$BUILD_DIR/external/iptables/iptables/xtables.lock"
    
    source build/envsetup.sh
    breakfast "$DEVICE"
    
    if m -j"$JOBS" bacon; then
        print_status "Build Success!"
        build_success=true
        mv "$BUILD_DIR/out/target/product/$DEVICE/"lineage-*.zip "$ZIPS_DIR/" 2>/dev/null
    else
        print_warning "Build attempt $build_attempt failed."
        ((build_attempt++))
        [ $build_attempt -le $MAX_RETRIES ] && make installclean
    fi
done

[ "$build_success" = false ] && { print_error "Build failed after $MAX_RETRIES attempts."; exit 1; }

# Step 13: Summary
print_step "BUILD COMPLETE - SUMMARY"
if [ "$build_success" = true ]; then
    echo ""
    echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║                                                            ║${NC}"
    echo -e "${BOLD}${GREEN}║              BUILD COMPLETED SUCCESSFULLY!                 ║${NC}"
    echo -e "${BOLD}${GREEN}║                                                            ║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    print_status "Your LineageOS build is ready!"
    
    if ls "$ZIPS_DIR/"*.zip 1> /dev/null 2>&1; then
        print_info "Output location: $ZIPS_DIR"
        echo ""
        print_info "Installation files:"
        ls -1 "$ZIPS_DIR/"*.zip 2>/dev/null | while read -r file; do
            local size
            size=$(du -h "$file" | cut -f1)
            echo "  • $(basename "$file") [$size]"
        done
    fi
    
    echo ""
    print_info "Next steps:"
    echo "  1. Copy the .zip file to your device"
    echo "  2. Boot into recovery mode"
    echo "  3. Flash the LineageOS .zip file"
    echo "  4. Reboot and enjoy!"
fi

echo ""
print_info "Total build time:"
show_elapsed_time $BUILD_START

echo ""
print_status "Script complete!"
echo ""
echo "Important notes:"
echo "- If blobs weren't extracted: cd $BUILD_DIR/device/google/$DEVICE && ./extract-files.sh"
echo "- To rebuild: cd $BUILD_DIR && source build/envsetup.sh && m -j$JOBS bacon"
if [ "$SKIP_SYNC" = true ]; then
    echo "- To rebuild faster: $0 --skip-sync"
fi
echo "- Build output zips: $ZIPS_DIR (or $BUILD_DIR/out/target/product/$DEVICE/)"
echo "- Factory images stored: $FACTORY_IMAGE_DIR"
echo ""
echo "Command line options:"
echo "  --skip-sync    Skip repo sync (useful for rebuilds)"
echo "  --help         Show usage information"
echo ""
print_info "For questions or issues, check: https://wiki.lineageos.org/devices/husky/"