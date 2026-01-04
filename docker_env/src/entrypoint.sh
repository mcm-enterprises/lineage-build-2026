#!/bin/bash
set -e

# --- 1. HOST UID MAPPING ---
# We detect the UID of the mounted volume to match permissions permissions
# If target dir is owned by 1000, we create user 1000 inside.
TARGET_UID=$(stat -c '%u' /android/lineage)
TARGET_GID=$(stat -c '%g' /android/lineage)

if [ "$TARGET_UID" == "0" ]; then
    echo ">> Warning: Mounted volume is owned by ROOT. Using 1000:1000 as default target."
    TARGET_UID=1000
    TARGET_GID=1000
fi

echo ">> Configured Build User: UID=$TARGET_UID GID=$TARGET_GID"

# Create the user if it doesn't exist
if ! id -u builder > /dev/null 2>&1; then
    groupadd -g $TARGET_GID builder || true
    useradd -u $TARGET_UID -g $TARGET_GID -m builder -s /bin/bash
    echo ">> Created internal user 'builder' to match host permissions."
    
    # Give sudo rights (passwordless) just in case
    echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

# Fix ownership of internal paths
chown builder:builder /android/lineage
chown -R builder:builder /home/builder

# Switch to the builder user to run the rest of the script
# We use 'su' to preserve environment variables, but we need to pass them explicitly or just run a sub-script.
# Actually, running the logic directly as 'su' is cleaner.

# Export variables for the sub-shell
export DEVICE=${DEVICE}
export BRANCH=${BRANCH}
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache

# --- THE BUILD LOGIC (Running as USER) ---
cat << 'EOF' > /home/builder/build_logic.sh
#!/bin/bash
set -e

echo ">> [$(date)] Starting Robust Build Logic..."

# 1. GIT CONFIG
git config --global user.email "dockerbuild@example.com"
git config --global user.name "Docker Builder"
git config --global --add safe.directory '*'

# 2. LOCAL MANIFESTS (TheMuppets) - DISABLED for Baremetal Parity
# We use local extraction instead.
rm -f .repo/local_manifests/muppets.xml 2>/dev/null || true

# 3. REPO INIT
if [ ! -d ".repo" ]; then
    echo ">> [$(date)] Initializing Repo..."
    repo init -u https://github.com/LineageOS/android.git -b $BRANCH --git-lfs
fi

# 4. ROBUST SYNC LOOP
echo ">> [$(date)] Starting Self-Healing Sync..."
MAX_RETRIES=100
COUNT=0
SUCCESS=0

while [ $COUNT -lt $MAX_RETRIES ]; do
    # Cleanup locks before every attempt
    find .repo -name "*.lock" -delete 2>/dev/null || true
    
    # Try sync
    if repo sync -j4 --force-sync --no-clone-bundle --no-tags; then
        SUCCESS=1
        break
    else
        echo ">> [$(date)] Sync failed (Attempt $COUNT/$MAX_RETRIES). Retrying in 10s..."
        sleep 10
        COUNT=$((COUNT+1))
    fi
done

if [ $SUCCESS -eq 0 ]; then
    echo ">> [$(date)] CRITICAL: Repo sync failed after $MAX_RETRIES attempts."
    exit 1
fi

# 5. EXTRACT BLOBS (Local Image Extraction)
echo ">> [$(date)] Starting Local Blob Extraction (Surgical Rescue)..."

EXTRACTED_IMAGES="/android/images/extracted"
MOUNT_BASE="/tmp/husky_mounts"
mkdir -p "$MOUNT_BASE/system" "$MOUNT_BASE/system_ext" "$MOUNT_BASE/product" "$MOUNT_BASE/vendor"

# Mount images (Requires privileged container)
sudo mount -t erofs,ext4 -o ro "$EXTRACTED_IMAGES/system.img" "$MOUNT_BASE/system" 2>/dev/null || echo "Warning: system.img mount failed"
sudo mount -t erofs,ext4 -o ro "$EXTRACTED_IMAGES/system_ext.img" "$MOUNT_BASE/system_ext" 2>/dev/null || echo "Warning: system_ext.img mount failed"
sudo mount -t erofs,ext4 -o ro "$EXTRACTED_IMAGES/product.img" "$MOUNT_BASE/product" 2>/dev/null || echo "Warning: product.img mount failed"
sudo mount -t erofs,ext4 -o ro "$EXTRACTED_IMAGES/vendor.img" "$MOUNT_BASE/vendor" 2>/dev/null || echo "Warning: vendor.img mount failed"

# Path to proprietary list (Try multiple common locations if structure varies)
PROPRIETARY_LIST="device/google/shusky/husky/proprietary-files.txt"
if [ ! -f "$PROPRIETARY_LIST" ]; then
    PROPRIETARY_LIST="device/google/husky/proprietary-files.txt"
fi

if [ -f "$PROPRIETARY_LIST" ]; then
    echo ">> Found proprietary list at $PROPRIETARY_LIST"
    # We focus on the files Ninja reported as missing
    CLEAN_LIST=$(grep -v '^#' "$PROPRIETARY_LIST" | grep -E '\.(xml|rc|pb|txt|img)$' | sed 's/^-//')

    for entry in $CLEAN_LIST; do
        dest_rel_path=$(echo "$entry" | cut -d':' -f1 | cut -d'|' -f1)
        target_filename=$(echo "$entry" | sed 's/.*[:|]//')
        full_dest_path="vendor/google/husky/proprietary/$dest_rel_path"
        
        if [ ! -f "$full_dest_path" ]; then
            # Using -name for just the filename to avoid the 'separator' warning
            base_search=$(basename "$target_filename")
            FOUND=$(sudo find "$MOUNT_BASE" -type f -name "$base_search" | head -n 1)

            if [ -n "$FOUND" ]; then
                mkdir -p "$(dirname "$full_dest_path")"
                sudo cp "$FOUND" "$full_dest_path"
                sudo chmod 644 "$full_dest_path"
                sudo chown builder:builder "$full_dest_path"
                echo "    [✓] Rescued: $base_search"
            fi
        fi
    done
else
    echo ">> WARNING: proprietary-files.txt not found. Skipping extraction."
fi

sudo umount -R "$MOUNT_BASE" 2>/dev/null || true


# 6. BUILD
echo ">> [$(date)] Environment Ready. Starting Build..."
source build/envsetup.sh
breakfast $DEVICE
croot
brunch $DEVICE

# 6. ARTIFACTS
mkdir -p /android/zips
mv out/target/product/$DEVICE/lineage-*.zip /android/zips/ 2>/dev/null || true
echo ">> [$(date)] Build Finished. Zips moved to output."
EOF

chmod +x /home/builder/build_logic.sh
chown builder:builder /home/builder/build_logic.sh

# EXECUTE AS USER
exec sudo -E -u builder /home/builder/build_logic.sh
