#!/bin/bash

# ============================================================================
# LineageOS 22.1 Build Script for Pixel 8 Pro (husky) - CLEAN VERSION
# ============================================================================

set -e

# --- CONFIGURATION ---
DEVICE="husky"
BRANCH="lineage-22.1"
BUILD_DIR="/media/BIG_STORAGE/lineageOS/android_source/LINEAGE_22_1"
JOBS=$(nproc --all)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[1;35m'
BOLD='\033[1m'
NC='\033[0m'

# Parse arguments
SKIP_SYNC=false
CLEAN_BUILD=false
for arg in "$@"; do
    [[ "$arg" == "--skip-sync" ]] && SKIP_SYNC=true
    [[ "$arg" == "--clean" ]] && CLEAN_BUILD=true
done

echo -e "\n${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${MAGENTA}║  LineageOS 22.1 Build for Pixel 8 Pro (husky)         ║${NC}"
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════╝${NC}\n"

# --- SYSTEM SETUP ---
echo -e "${CYAN}[→] Configuring system...${NC}"
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 2>/dev/null || true

export OVERRIDE_BUILD_DATE=1743465600
export BUILD_DATETIME_CHECK=false
export LC_ALL=C

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit 1

# --- CLEANUP ---
echo -e "${CYAN}[→] Cleaning stale locks...${NC}"
find .repo -name "*.lock" -delete 2>/dev/null || true
find . -name "index.lock" -delete 2>/dev/null || true

# --- REPO INIT ---
if [ ! -d ".repo" ]; then
    echo -e "${YELLOW}[!] Initializing repository...${NC}"
    repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs --depth=1
    SKIP_SYNC=false
else
    CURRENT_BRANCH=$(repo info 2>/dev/null | grep "Manifest branch:" | head -1 | awk '{print $3}')
    CURRENT_BRANCH_NORMALIZED="${CURRENT_BRANCH#refs/heads/}"
    
    if [ "$CURRENT_BRANCH_NORMALIZED" != "$BRANCH" ]; then
        echo -e "${YELLOW}[!] Re-initializing to $BRANCH...${NC}"
        repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs
        SKIP_SYNC=false
    else
        echo -e "${GREEN}[✓] Already on $BRANCH${NC}"
    fi
fi

# Remove any local manifests - not needed for LineageOS 22.1
rm -rf .repo/local_manifests 2>/dev/null || true

# --- SYNC ---
if [ "$SKIP_SYNC" = false ]; then
    echo -e "\n${CYAN}[→] Syncing source ($JOBS jobs)...${NC}"
    repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags || {
        echo -e "${YELLOW}[!] Retrying with single job...${NC}"
        repo sync -c -j1 --force-sync --no-clone-bundle --no-tags
    }
    echo -e "${GREEN}[✓] Sync complete${NC}"
else
    echo -e "${GREEN}[✓] Skipping sync${NC}"
fi

# --- BUILD ENVIRONMENT ---
echo -e "\n${CYAN}[→] Setting up build environment...${NC}"
source build/envsetup.sh
breakfast "$DEVICE"

unset CC_WRAPPER CCACHE_EXEC USE_CCACHE

# --- CLEAN BUILD ---
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${YELLOW}[→] Clean build: removing out/...${NC}"
    rm -rf out/
fi

# --- BUILD ---
echo -e "\n${BOLD}${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║  Starting Build (2-6 hours)                            ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════╝${NC}\n"

START_TIME=$(date +%s)

if m bacon -j"$JOBS"; then
    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    BUILD_HOURS=$((BUILD_TIME / 3600))
    BUILD_MINUTES=$(((BUILD_TIME % 3600) / 60))
    
    echo -e "\n${BOLD}${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║  BUILD SUCCESSFUL! 🎉                                  ║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}Build time: ${BUILD_HOURS}h ${BUILD_MINUTES}m${NC}"
    echo -e "${GREEN}Output: $(ls -lh out/target/product/$DEVICE/lineage-*.zip 2>/dev/null | tail -1 | awk '{print $9}')${NC}\n"
else
    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    BUILD_MINUTES=$((BUILD_TIME / 60))
    
    echo -e "\n${BOLD}${RED}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${RED}║  BUILD FAILED ✗                                        ║${NC}"
    echo -e "${BOLD}${RED}╚════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${RED}Failed after: ${BUILD_MINUTES}m${NC}\n"
    exit 1
fi