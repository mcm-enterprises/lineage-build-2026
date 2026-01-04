#!/bin/bash

# LineageOS 22.1 Build Script for Pixel 8 Pro (husky)
# For Ubuntu 25.10

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

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-sync    Skip repo sync step (use if code already downloaded)"
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
# Use relative paths matching build-husky-baremetal.sh
SCRIPT_DIR="$(pwd)"
SRC_NAME="android_source/LINEAGE_22_1"
BUILD_DIR="$SCRIPT_DIR/$SRC_NAME"
REPO_URL="https://github.com/LineageOS/android.git"
MAX_RETRIES=5
# Job control (default to all cores, change to reduce load)
JOBS=$(nproc --all)
FACTORY_IMAGE_DIR="$SCRIPT_DIR/images"
FACTORY_IMAGE_URL="https://dl.google.com/dl/android/aosp"
ZIPS_DIR="$SCRIPT_DIR/zips"
LOG_DIR="$SCRIPT_DIR/logs"
MANIFEST_DIR="$SCRIPT_DIR/local_manifests"

# Step counter (adjust based on skip flags)
CURRENT_STEP=0
TOTAL_STEPS=12
if [ "$SKIP_SYNC" = true ]; then
    TOTAL_STEPS=10
fi

# Function to print step header
print_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo -e "${BOLD}${CYAN}STEP $CURRENT_STEP/$TOTAL_STEPS: $1${NC}"
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo ""
}

# Function to print sub-step
print_substep() {
    echo -e "${BLUE}  ► $1${NC}"
}

# Function to print colored messages
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${MAGENTA}[ℹ]${NC} $1"
}

print_progress() {
    echo -e "${CYAN}[→]${NC} $1"
}

# Function to show time elapsed
show_elapsed_time() {
    local start_time=$1
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))
    local seconds=$((elapsed % 60))
    echo -e "${GREEN}[✓] Time elapsed: ${hours}h ${minutes}m ${seconds}s${NC}"
}

echo ""
echo -e "${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${MAGENTA}║                                                            ║${NC}"
echo -e "${BOLD}${MAGENTA}║   LineageOS 22.1 Build Script for Pixel 8 Pro (husky)     ║${NC}"
echo -e "${BOLD}${MAGENTA}║                   Ubuntu 25.10                             ║${NC}"
echo -e "${BOLD}${MAGENTA}║                                                            ║${NC}"
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
print_info "Total Steps: $TOTAL_STEPS"
print_info "Build Directory: $BUILD_DIR"
print_info "Device: $DEVICE"
if [ "$SKIP_SYNC" = true ]; then
    print_warning "Skip Sync: ENABLED (repo sync will be skipped)"
fi
echo ""

# Function to kill previous instances
kill_previous_instances() {
    print_substep "Killing any previous build processes..."
    pkill -f "build_lineage.sh" || true
    pkill -f "repo sync" || true
    pkill -f "brunch" || true
    sleep 2
    print_status "Process cleanup complete"
}

# Function to remove lock files
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
    else
        print_info "Build directory doesn't exist yet"
    fi
}

# Function to get latest factory image info
get_latest_factory_image() {
    print_substep "Fetching latest factory image information..."
    
    # Download the factory images page to parse it
    local temp_page="/tmp/factory_images.html"
    curl -s "https://developers.google.com/android/images" -o "$temp_page"
    
    # Extract the latest husky factory image filename
    local latest_image
    latest_image=$(grep -o "husky-[a-z0-9.-]*-factory-[a-z0-9]*.zip" "$temp_page" | head -1)
    
    if [ -z "$latest_image" ]; then
        print_warning "Could not auto-detect latest image"
        return 1
    fi
    
    print_status "Detected: $latest_image"
    echo "$latest_image"
    return 0
}

# Function to verify download URL
verify_download_url() {
    local url="$1"
    local filename="$2"
    
    print_substep "Verifying download URL is accessible..."
    print_info "URL: $url"
    
    # Try HEAD request to check if URL exists
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -I "$url")
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
        print_status "URL verification successful (HTTP $http_code)"
        
        # Try to get file size if available
        local content_length
        content_length=$(curl -sI "$url" | grep -i "content-length" | awk '{print $2}' | tr -d '\r')
        if [ -n "$content_length" ]; then
            local size_mb=$((content_length / 1024 / 1024))
            print_info "File size: ${size_mb}MB"
        fi
        
        return 0
    elif [ "$http_code" = "404" ]; then
        print_error "URL not found (HTTP 404)"
        print_warning "The factory image may have been removed or renamed"
        return 1
    else
        print_warning "URL check returned HTTP $http_code"
        print_info "Will attempt download anyway..."
        return 0
    fi
}

# Function to download and extract factory image
download_factory_image() {
    print_substep "Checking factory image status..."
    
    mkdir -p "$FACTORY_IMAGE_DIR"
    cd "$FACTORY_IMAGE_DIR" || exit 1
    
    # Check if we already have a factory image
    local existing_image
    existing_image=$(ls husky-*-factory-*.zip 2>/dev/null | head -1)
    
    if [ -n "$existing_image" ]; then
        print_status "Found existing factory image: $existing_image"
        print_info "Skipping download (already present)"
        
        # Verify the existing file is valid
        print_substep "Verifying existing file integrity..."
        if unzip -t "$existing_image" &>/dev/null; then
            print_status "Existing file is valid"
            echo "$FACTORY_IMAGE_DIR/$existing_image"
            return 0
        else
            print_warning "Existing file appears corrupted, will re-download"
            rm -f "$existing_image"
        fi
    fi
    
    print_progress "No valid existing image found, will download..."
    
    local image_name
    image_name=$(get_latest_factory_image)
    
    if [ -z "$image_name" ]; then
        print_warning "Auto-detection failed, using fallback image name"
        image_name="husky-ap4a.250205.002.b2-factory-81c3d0c5.zip"
    fi
    
    local download_url="$FACTORY_IMAGE_URL/$image_name"
    local local_file="$FACTORY_IMAGE_DIR/$image_name"
    
    # Verify URL before attempting download
    if ! verify_download_url "$download_url" "$image_name"; then
        print_error "URL verification failed"
        print_warning "Trying alternative URLs..."
        
        # Try alternative fallback URLs
        local alt_images=(
            "husky-ap31.240617.015-factory-d78a8e0f.zip"
            "husky-ap2a.240805.005-factory-3b6e37c8.zip"
            "husky-ap1a.240505.005-factory-2f6e29a5.zip"
        )
        
        local found_alt=false
        for alt_image in "${alt_images[@]}"; do
            local alt_url="$FACTORY_IMAGE_URL/$alt_image"
            print_info "Trying: $alt_image"
            
            if verify_download_url "$alt_url" "$alt_image"; then
                download_url="$alt_url"
                local_file="$FACTORY_IMAGE_DIR/$alt_image"
                image_name="$alt_image"
                print_status "Found working alternative URL"
                found_alt=true
                break
            fi
        done
        
        if [ "$found_alt" = false ]; then
            print_error "All URL verification attempts failed"
            print_info "You can manually download from: https://developers.google.com/android/images"
            return 1
        fi
    fi
    
    print_progress "Download URL verified and ready"
    print_warning "Factory image is ~2-3GB, this will take time..."
    echo ""
    
    # Attempt download with retries
    local download_attempt=1
    local max_download_attempts=3
    
    while [ $download_attempt -le $max_download_attempts ]; do
        print_progress "Download attempt $download_attempt of $max_download_attempts"
        
        if wget --progress=bar:force -c "$download_url" -O "$local_file"; then
            print_status "Download completed!"
            
            # Verify downloaded file
            print_substep "Verifying downloaded file..."
            if unzip -t "$local_file" &>/dev/null; then
                print_status "File integrity verified"
                local size
                size=$(du -h "$local_file" | cut -f1)
                print_info "Size: $size"
                echo "$local_file"
                return 0
            else
                print_error "Downloaded file is corrupted"
                rm -f "$local_file"
                
                if [ $download_attempt -lt $max_download_attempts ]; then
                    print_progress "Retrying download..."
                    sleep 5
                fi
            fi
        else
            print_warning "Download attempt $download_attempt failed"
            
            if [ $download_attempt -lt $max_download_attempts ]; then
                print_progress "Retrying in 10 seconds..."
                sleep 10
            fi
        fi
        
        download_attempt=$((download_attempt + 1))
    done
    
    print_error "Failed to download factory image after $max_download_attempts attempts"
    return 1
}

# Function to extract proprietary blobs
extract_proprietary_blobs() {
    print_substep "Starting blob extraction process..."
    
    local factory_image="$1"
    
    if [ ! -f "$factory_image" ]; then
        print_error "Factory image not found: $factory_image"
        return 1
    fi
    
    print_info "Factory image: $(basename "$factory_image")"
    
    # Extract the factory image
    local extract_dir="$FACTORY_IMAGE_DIR/extracted"
    
    # Check if already extracted
    if [ -d "$extract_dir" ] && [ "$(ls -A "$extract_dir" 2>/dev/null)" ]; then
        print_status "Factory image already extracted"
        print_info "Location: $extract_dir"
    else
        mkdir -p "$extract_dir"
        print_progress "Unzipping factory image (this may take a few minutes)..."
        unzip -q -o "$factory_image" -d "$extract_dir"
        print_status "Factory image extracted"
        
        # Find and extract the inner image-*.zip file
        local inner_zip
        inner_zip=$(find "$extract_dir" -name "image-*.zip" | head -1)
        
        if [ -n "$inner_zip" ]; then
            print_progress "Extracting inner image archive..."
            unzip -q -o "$inner_zip" -d "$extract_dir"
            print_status "Inner archive extracted"
        fi
    fi
    
    # Now run the extraction script
    cd "$BUILD_DIR/device/google/$DEVICE" || return 1
    
    if [ ! -f "extract-files.sh" ]; then
        print_error "extract-files.sh not found in device tree"
        return 1
    fi
    
    print_progress "Running LineageOS blob extraction script..."
    chmod +x extract-files.sh
    
    # Run extraction with visible output
    if ./extract-files.sh "$extract_dir" 2>&1 | while IFS= read -r line; do
        echo "  $line"
    done; then
        print_status "Proprietary blobs extracted successfully!"
        return 0
    else
        print_warning "Extraction may have encountered issues"
        return 1
    fi
}

# Function to retry command
retry_command() {
    local cmd="$1"
    local max_attempts="$2"
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        print_progress "Attempt $attempt of $max_attempts"
        if eval "$cmd"; then
            print_status "Command succeeded"
            return 0
        else
            if [ $attempt -lt $max_attempts ]; then
                print_warning "Attempt $attempt failed, retrying in 10 seconds..."
                sleep 10
            fi
            attempt=$((attempt + 1))
        fi
    done
    
    print_error "Command failed after $max_attempts attempts"
    return 1
}

# Cleanup before starting
print_step "CLEANUP & PREPARATION"
STEP_START=$(date +%s)
kill_previous_instances
remove_lock_files
show_elapsed_time $STEP_START

# Step 1: Install dependencies
print_step "INSTALL BUILD DEPENDENCIES"
STEP_START=$(date +%s)
print_substep "Updating package lists..."
sudo apt-get update
print_substep "Installing required packages..."
sudo apt-get install -y \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib git \
    git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev \
    liblz4-tool libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop \
    pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev \
    openjdk-17-jdk python3 python-is-python3 adb fastboot wget unzip

print_substep "Configuring kernel for build sandboxing..."
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0

print_status "All dependencies installed"
show_elapsed_time $STEP_START

# Step 2: Install repo tool
print_step "INSTALL REPO TOOL"
STEP_START=$(date +%s)
print_substep "Creating ~/.bin directory..."
mkdir -p ~/.bin
PATH="${HOME}/.bin:${PATH}"
print_substep "Downloading repo tool..."
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo
chmod a+rx ~/.bin/repo
print_status "Repo tool installed"

# Add to PATH permanently if not already there
if ! grep -q 'PATH="${HOME}/.bin:${PATH}"' ~/.bashrc; then
    echo 'PATH="${HOME}/.bin:${PATH}"' >> ~/.bashrc
    print_info "Added repo to PATH in ~/.bashrc"
fi
show_elapsed_time $STEP_START

# Step 3: Configure git
print_step "CONFIGURE GIT"
STEP_START=$(date +%s)
if [ -z "$(git config --global user.email)" ]; then
    print_warning "Git email not configured"
    echo "Please enter your email for git:"
    read -r git_email
    git config --global user.email "$git_email"
    print_status "Git email set to: $git_email"
else
    print_status "Git email already configured: $(git config --global user.email)"
fi

if [ -z "$(git config --global user.name)" ]; then
    print_warning "Git name not configured"
    echo "Please enter your name for git:"
    read -r git_name
    git config --global user.name "$git_name"
    print_status "Git name set to: $git_name"
else
    print_status "Git name already configured: $(git config --global user.name)"
fi
show_elapsed_time $STEP_START

# Step 4: Create build directory
print_step "CREATE BUILD DIRECTORY"
STEP_START=$(date +%s)
print_substep "Creating directories..."
mkdir -p "$BUILD_DIR" "$ZIPS_DIR" "$LOG_DIR" "$MANIFEST_DIR" "$FACTORY_IMAGE_DIR"
cd "$BUILD_DIR" || exit 1
print_status "Build directory ready: $BUILD_DIR"
print_info "Total space available: $(df -h "$BUILD_DIR" | awk 'NR==2 {print $4}')"
show_elapsed_time $STEP_START

# Step 5: Initialize repo
print_step "INITIALIZE LINEAGEOS REPOSITORY"
STEP_START=$(date +%s)

if [ "$SKIP_SYNC" = true ]; then
    print_warning "Skipping repo initialization (--skip-sync enabled)"
    
    # Check if repo is already initialized
    if [ -d "$BUILD_DIR/.repo" ]; then
        print_status "Repository already initialized"
    else
        print_error "Repository not initialized and --skip-sync is enabled!"
        print_info "Either run without --skip-sync or initialize manually with:"
        echo "  cd $BUILD_DIR && repo init -u $REPO_URL -b $LINEAGE_VERSION --git-lfs"
        exit 1
    fi
else
    remove_lock_files
    print_substep "Running: repo init -u $REPO_URL -b $LINEAGE_VERSION"
    retry_command "repo init -u '$REPO_URL' -b '$LINEAGE_VERSION' --git-lfs" 3
    print_status "Repository initialized"
fi

show_elapsed_time $STEP_START

# Step 6: Copy Local Manifests
print_step "COPY LOCAL MANIFESTS"
STEP_START=$(date +%s)
print_substep "Cleaning old manifests..."
rm -rf .repo/local_manifests
mkdir -p .repo/local_manifests

if ls "$MANIFEST_DIR"/*.xml 1> /dev/null 2>&1; then
    print_progress "Found local manifests, copying..."
    cp "$MANIFEST_DIR"/*.xml .repo/local_manifests/
    print_status "Copied local manifests from $MANIFEST_DIR"
else
    print_warning "No local manifests found in $MANIFEST_DIR"
fi
show_elapsed_time $STEP_START

# Step 7: Download source code
if [ "$SKIP_SYNC" = true ]; then
    print_step "DOWNLOAD LINEAGEOS SOURCE CODE"
    STEP_START=$(date +%s)
    print_warning "SKIPPED: Repo sync disabled with --skip-sync flag"
    print_info "Using existing source code in $BUILD_DIR"
    
    # Verify source code exists
    if [ -d "$BUILD_DIR/.repo" ] && [ -d "$BUILD_DIR/build" ]; then
        print_status "Source code directory verified"
    else
        print_error "Source code appears incomplete!"
        print_warning "Missing critical directories. You may need to run without --skip-sync"
        exit 1
    fi
    show_elapsed_time $STEP_START
else
    print_step "DOWNLOAD LINEAGEOS SOURCE CODE"
    STEP_START=$(date +%s)
    print_warning "This will download ~150GB of source code"
    print_info "Using $JOBS jobs for parallel download"
    remove_lock_files

    # Try repo sync with retries
    sync_attempt=1
    while [ $sync_attempt -le $MAX_RETRIES ]; do
        print_substep "Repo sync attempt $sync_attempt of $MAX_RETRIES"
        echo ""
        
        if repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags; then
            print_status "Source code download complete!"
            break
        else
            print_warning "Repo sync failed"
            remove_lock_files
            if [ $sync_attempt -eq $MAX_RETRIES ]; then
                print_error "Repo sync failed after $MAX_RETRIES attempts"
                exit 1
            fi
            print_progress "Cleaning up and retrying in 15 seconds..."
            sleep 15
            sync_attempt=$((sync_attempt + 1))
        fi
    done
    show_elapsed_time $STEP_START
fi

# Step 8: Extract proprietary blobs
print_step "DOWNLOAD & EXTRACT PROPRIETARY BLOBS"
STEP_START=$(date +%s)

# First, try to download and extract from factory image
factory_image_path=$(download_factory_image)
blob_status=$?

if [ $blob_status -eq 0 ] && [ -n "$factory_image_path" ]; then
    echo ""
    if extract_proprietary_blobs "$factory_image_path"; then
        print_status "Blobs successfully extracted from factory image!"
    else
        print_warning "Factory image extraction had issues, trying device..."
        
        cd "$BUILD_DIR/device/google/$DEVICE" || exit 1
        
        if adb devices | grep -q "device$"; then
            print_progress "Device detected, extracting from device..."
            if ./extract-files.sh; then
                print_status "Blobs extracted from connected device!"
            else
                print_error "Device extraction also failed"
                print_warning "Continuing anyway - build may fail"
            fi
        else
            print_warning "No device connected, continuing without blobs"
            print_info "You can extract later with:"
            echo "    cd $BUILD_DIR/device/google/$DEVICE && ./extract-files.sh"
        fi
    fi
else
    print_warning "Factory image download failed, trying device..."
    
    cd "$BUILD_DIR/device/google/$DEVICE" || exit 1
    
    if adb devices | grep -q "device$"; then
        print_progress "Device detected, extracting from device..."
        if ./extract-files.sh; then
            print_status "Blobs extracted from connected device!"
        fi
    else
        print_warning "No device connected and download failed"
        print_info "Manual extraction needed later"
    fi
fi

cd "$BUILD_DIR" || exit 1
show_elapsed_time $STEP_START

# Step 9: Setup ccache
print_step "CONFIGURE CCACHE"
STEP_START=$(date +%s)
print_substep "Enabling ccache for faster builds..."
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
print_substep "Setting cache size to 50GB..."
ccache -M 50G
print_status "Ccache configured"
print_info "Current cache status:"
ccache -s | grep -E "cache directory|cache size|max cache size" | sed 's/^/  /'
show_elapsed_time $STEP_START

# Step 10: Prepare device-specific code
print_step "PREPARE DEVICE-SPECIFIC CODE"
STEP_START=$(date +%s)
print_substep "Sourcing build environment..."
source build/envsetup.sh
print_substep "Running breakfast for device: $DEVICE"
breakfast "$DEVICE"
print_status "Device-specific preparation complete"
show_elapsed_time $STEP_START

# Step 11: Build LineageOS
print_step "BUILD LINEAGEOS"
BUILD_START=$(date +%s)
print_warning "This will take 4-8 hours depending on your hardware"
print_info "Build will retry up to $MAX_RETRIES times if it fails"

# Build with retry logic
build_attempt=1
build_success=false

while [ $build_attempt -le $MAX_RETRIES ] && [ "$build_success" = false ]; do
    print_substep "Build attempt $build_attempt of $MAX_RETRIES"
    ATTEMPT_START=$(date +%s)
    
    # Clean up build locks
    remove_lock_files
    
    # --- CRITICAL FIXES FOR UBUNTU 25.10 ---
    export LC_ALL=C
    export OVERRIDE_BUILD_DATE=$(date +%s)
    export BUILD_DATETIME_CHECK=false
    # Ensure sandboxing is allowed for this attempt
    sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true
    # ---------------------------------------

    # Source environment
    cd "$BUILD_DIR" || exit 1
    source build/envsetup.sh
    breakfast "$DEVICE"
    
    echo ""
    print_progress "Starting compilation..."
    print_info "You can monitor progress in real-time below"
    echo ""
    echo -e "${BOLD}${CYAN}==================== BUILD OUTPUT ====================${NC}"
    
    # Start build with output shown
    if m -j"$JOBS" bacon; then
        echo -e "${BOLD}${CYAN}=====================================================${NC}"
        echo ""
        print_status "Build completed successfully!"
        build_success=true
        
        # Move build artifacts
        print_info "Moving artifacts to $ZIPS_DIR..."
        if mv "$BUILD_DIR/out/target/product/$DEVICE/"lineage-*.zip "$ZIPS_DIR/" 2>/dev/null; then
            print_status "Zips moved to $ZIPS_DIR"
        else
            print_warning "Could not move zips (they may still be in out/target/product/$DEVICE/)"
        fi
        
        # Show build artifacts
        print_info "Build artifacts:"
        if ls "$ZIPS_DIR/"*.zip 1> /dev/null 2>&1; then
            ls -lh "$ZIPS_DIR/"*.zip 2>/dev/null | while read -r line; do
                echo "  $line"
            done
        else
            ls -lh "$BUILD_DIR/out/target/product/$DEVICE/"*.zip 2>/dev/null | while read -r line; do
                echo "  $line"
            done
        fi
    else
        echo -e "${BOLD}${CYAN}=====================================================${NC}"
        echo ""
        print_warning "Build attempt $build_attempt failed"
        show_elapsed_time $ATTEMPT_START
        
        if [ $build_attempt -lt $MAX_RETRIES ]; then
            print_progress "Cleaning build artifacts..."
            
            # Clean output directory
            make clean 2>/dev/null || true
            
            # Remove lock files again
            remove_lock_files
            
            print_progress "Waiting 30 seconds before retry..."
            sleep 30
        else
            print_error "Build failed after $MAX_RETRIES attempts"
            print_error "Please check the error messages above"
            echo ""
            print_info "To retry manually, run:"
            echo "  cd $BUILD_DIR"
            echo "  source build/envsetup.sh"
            echo "  breakfast $DEVICE"
            echo "  m -j$JOBS bacon"
            exit 1
        fi
    fi
    
    build_attempt=$((build_attempt + 1))
done

show_elapsed_time $BUILD_START

# Step 12: Summary
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
    else
        print_info "Output location: $BUILD_DIR/out/target/product/$DEVICE/"
        echo ""
        print_info "Installation files:"
        ls -1 "$BUILD_DIR/out/target/product/$DEVICE/"*.zip 2>/dev/null | while read -r file; do
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