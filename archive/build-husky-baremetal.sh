#!/bin/bash
set -e

# --- CONFIGURATION (Stable) ---
# We use 'android_source' as the main source tree
SRC_DIR="android_source/LINEAGE_22_1"
LOG_DIR="logs"
ZIPS_DIR="zips"
MANIFEST_DIR="local_manifests"
IMAGES_DIR="images"

# Factory Image Details (Android 15 - BP1A.250505.005.B1)
FACTORY_IMAGE_URL="https://dl.google.com/dl/android/aosp/husky-bp1a.250505.005.b1-factory-29f5f55f.zip"
FACTORY_IMAGE_ZIP="husky-bp1a.250505.005.b1-factory-29f5f55f.zip"

DEVICE="husky"
BRANCH="lineage-22.1"
# No Vendor Override needed for stable branch
# VENDOR_BRANCH="lineage-22.1"

# 0. Kill competing instances and repo syncs
echo ">> [$(date)] Killing any existing build or sync processes..."
# Kill other instances of this script (excluding self)
for pid in $(pgrep -f "build-husky-baremetal.sh"); do
    if [ "$pid" != "$$" ]; then
        echo "   Killing previous build script instance (PID $pid)..."
        kill -9 "$pid" 2>/dev/null || true
    fi
done

# Kill repo sync and git processes (Force Clean Start)
pkill -f "repo sync" || true
pkill -f "git-remote-https" || true

echo "   Waiting 5s for processes to terminate..."
sleep 5

# 1. Create Directories (if not exist)
mkdir -p "$SRC_DIR" "$LOG_DIR" "$ZIPS_DIR" "$MANIFEST_DIR" "$IMAGES_DIR"

# 2. Prepare Factory Image (for extraction)
if [ -f "$IMAGES_DIR/$FACTORY_IMAGE_ZIP" ]; then
    echo ">> [$(date)] Factory image found: $IMAGES_DIR/$FACTORY_IMAGE_ZIP"
else
    echo ">> [$(date)] Downloading Factory Image ($FACTORY_IMAGE_ZIP)..."
    wget -P "$IMAGES_DIR" "$FACTORY_IMAGE_URL"
fi

# 2. Configure Local Manifests (Official Method: using extract-files.sh)
# Removing unofficial Muppets manifest to prevent sync errors
if [ -f "$MANIFEST_DIR/muppets_husky.xml" ]; then
    rm "$MANIFEST_DIR/muppets_husky.xml"
    echo ">> [$(date)] Removed unofficial Muppets manifest."
fi


# 3. Enter Source Directory
cd "$SRC_DIR"

# 4. Initialize Repo
echo ">> [$(date)] Initializing/Updating Repo for branch $BRANCH..."
export PATH=~/bin:$PATH
repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs

# 5. Copy Manifests
# Ensure .repo/local_manifests is clean (remove potential ghosts)
rm -rf .repo/local_manifests
mkdir -p .repo/local_manifests

if ls ../../$MANIFEST_DIR/*.xml 1> /dev/null 2>&1; then
    cp ../../$MANIFEST_DIR/*.xml .repo/local_manifests/
    echo "   Copied local manifests."
else
    echo "   No local manifests to copy (Skipping)."
fi

# 5.5. Cleanup Stale Locks
echo ">> [$(date)] Cleaning up stale lock files..."
find . -name "index.lock" -delete
find .repo -name "*.lock" -delete || true

# 6. Sync Source
echo ">> [$(date)] Syncing source code (This will take hours)..."
repo sync -j8 --force-sync

# 6.5. Extract Blobs (Automated)
if [ -d "vendor/google/husky/proprietary" ]; then
    echo ">> [$(date)] Vendor blobs already present. Skipping extraction."
else
    echo ">> [$(date)] Extracting vendor blobs..."
    mkdir -p "$IMAGES_DIR/extracted/partitions"
    echo "   Unzipping factory image partitions..."
    # Unzip the nested zip file directly if possible, or the main zip then nested
    unzip -o "$IMAGES_DIR/$FACTORY_IMAGE_ZIP" -d "$IMAGES_DIR/extracted"
    # Find the nested zip (standard Google format)
    NESTED_ZIP=$(find "$IMAGES_DIR/extracted" -name "image-*.zip" | head -n 1)
    if [ -f "$NESTED_ZIP" ]; then
        unzip -o "$NESTED_ZIP" -d "$IMAGES_DIR/extracted/partitions"
        echo "   Running extract-files.py..."
        # Execute extraction
        (cd device/google/husky && ./extract-files.py "$IMAGES_DIR/extracted/partitions")
    else
        echo "ERROR: Could not find nested image zip in extracted folder."
        exit 1
    fi
fi

# 7. Start Build
echo ">> [$(date)] Starting Build for $DEVICE..."
source build/envsetup.sh
# Clean previous output
rm -rf out/
breakfast "$DEVICE"
croot
brunch "$DEVICE"

# 8. Move Output
if [ -f "out/target/product/$DEVICE/lineage-*.zip" ]; then
    echo ">> [$(date)] Build Successful! Moving zips..."
    mv out/target/product/$DEVICE/lineage-*.zip ../../$ZIPS_DIR/
    echo ">> [$(date)] Zips saved to $ZIPS_DIR"
else
    echo ">> [$(date)] Build finished (check logs for success/failure)."
fi
