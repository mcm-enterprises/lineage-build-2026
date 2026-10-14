#!/usr/bin/env bash
# Shared host/container workflow. Deliberately support one verified device/branch.
set -Eeo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/bin:$PATH"
export LC_ALL=C
DEVICE=husky
BRANCH=${BRANCH:-lineage-22.1}
BUILD_DIR=${BUILD_DIR:-$SCRIPT_DIR/android_source/LINEAGE_22_1}
OUTPUT_DIR=${OUTPUT_DIR:-$SCRIPT_DIR/zips}
LOG_DIR=${LOG_DIR:-$SCRIPT_DIR/logs}
SYNC_JOBS=${SYNC_JOBS:-4}
SYNC_RETRIES=${SYNC_RETRIES:-3}
SYNC_RETRY_DELAY=${SYNC_RETRY_DELAY:-15}
MIN_FREE_GB=${MIN_FREE_GB:-300}
ACTION=${1:-all}
fail() { echo "ERROR: $*" >&2; exit 1; }
usage() {
    echo "Usage: $0 [check|sync|build|all]"
    echo "Defaults: husky, lineage-22.1. Set BUILD_DIR, OUTPUT_DIR, JOBS, SYNC_JOBS as needed."
}
case "$ACTION" in
    -h|--help) usage; exit 0 ;;
    check|sync|build|all) ;;
    *) usage; exit 2 ;;
esac
[[ $# -le 1 ]] || fail "Only one action is accepted."
[[ "$BRANCH" == lineage-22.1 ]] || fail "Only lineage-22.1 is configured. Use a separate, verified manifest for another release."
for value in "$SYNC_JOBS" "$SYNC_RETRIES" "$MIN_FREE_GB"; do
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "Job, retry and disk limits must be positive integers."
done
[[ "$SYNC_RETRY_DELAY" =~ ^[0-9]+$ ]] || fail "SYNC_RETRY_DELAY must be a nonnegative integer."
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail "An x86_64 Linux host is required."
[[ $EUID -ne 0 ]] || fail "Run as your regular user, not root."
for tool in repo git python3 flock rsync; do
    command -v "$tool" >/dev/null || fail "Missing $tool. Run setup_build_env.sh or use Docker."
done
git lfs version >/dev/null || fail "git-lfs is required for vendor blobs."
git var GIT_AUTHOR_IDENT >/dev/null 2>&1 || fail "Configure git user.name and user.email first."
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$LOG_DIR"
BUILD_DIR=$(cd "$BUILD_DIR" && pwd -P)
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd -P)
LOG_DIR=$(cd "$LOG_DIR" && pwd -P)
# Hold this descriptor through repo and the build; never unlink the lock file.
exec 9>"$BUILD_DIR/.lineage-build.lock"
flock -n 9 || fail "Another workflow is using $BUILD_DIR."
LOG_FILE="$LOG_DIR/husky-$(date +%Y%m%d-%H%M%S)-$$.log"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'code=$?; echo "ERROR: line $LINENO failed (exit $code). Log: $LOG_FILE" >&2; exit "$code"' ERR
cd "$BUILD_DIR"
free_gb=$(df -Pk . | awk 'NR==2 {print int($4/1024/1024)}')
[[ "$free_gb" -ge "$MIN_FREE_GB" ]] || fail "Only ${free_gb} GiB free; require ${MIN_FREE_GB}. For an existing tree, set MIN_FREE_GB to your remaining-space budget."
mem_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
# Respect a container memory limit when present.
if [[ -r /sys/fs/cgroup/memory.max ]]; then
    limit=$(cat /sys/fs/cgroup/memory.max)
    if [[ "$limit" =~ ^[0-9]+$ ]] && (( limit / 1024 < mem_kb )); then mem_kb=$((limit / 1024)); fi
fi
memory_jobs=$((mem_kb / 1024 / 1024 / 4))
(( memory_jobs > 0 )) || memory_jobs=1
cpu_jobs=$(nproc)
if (( memory_jobs < cpu_jobs )); then cpu_jobs=$memory_jobs; fi
JOBS=${JOBS:-$cpu_jobs}
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || fail "JOBS must be a positive integer."
if (( mem_kb < 32 * 1024 * 1024 )); then echo "WARNING: Less than 32 GiB RAM available. Soong may require additional RAM/swap even with JOBS=$JOBS."; fi
echo "Device=$DEVICE Branch=$BRANCH Build=$BUILD_DIR Jobs=$JOBS SyncJobs=$SYNC_JOBS"
echo "Log: $LOG_FILE"
# Refuse old manifests rather than silently mixing or discarding a user's tree.
python3 "$SCRIPT_DIR/scripts/check_manifest.py" "$BUILD_DIR/.repo/local_manifests"
if [[ -d .repo/manifests/.git ]]; then
    existing_branch=$(git -C .repo/manifests config --get branch.default.merge)
    [[ "$existing_branch" == "refs/heads/$BRANCH" ]] || fail "Existing manifest branch is $existing_branch. Use a separate BUILD_DIR for $BRANCH."
fi
if [[ "$ACTION" == check ]]; then echo "Preflight passed. No source downloaded or compilation started."; exit 0; fi
sync_sources() {
    # .repo may exist after a failed init; always run the idempotent init first.
    repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs --no-clone-bundle
    mkdir -p .repo/local_manifests
    cp "$SCRIPT_DIR/local_manifests/husky.xml" .repo/local_manifests/husky.xml
    local attempt
    for ((attempt=1; attempt<=SYNC_RETRIES; attempt++)); do
        if repo sync -c -j"$SYNC_JOBS" --no-clone-bundle --no-tags --fail-fast; then return 0; fi
        echo "Sync attempt $attempt/$SYNC_RETRIES failed."
        if (( attempt < SYNC_RETRIES )); then sleep "$SYNC_RETRY_DELAY"; fi
    done
    fail "Source sync failed. Fix the first reported repository/network error, then rerun sync."
}
if [[ "$ACTION" == sync || "$ACTION" == all ]]; then sync_sources; fi
if [[ "$ACTION" == sync ]]; then echo "Sync complete."; exit 0; fi
[[ -f build/envsetup.sh ]] || fail "Missing source tree. Run sync first."
python3 "$SCRIPT_DIR/scripts/check_vendor.py" "$BUILD_DIR"
# Remove inherited workaround flags; use the toolchain shipped with this branch.
unset USE_CCACHE CCACHE_DIR CCACHE_EXEC CC_WRAPPER TEMPORARY_DISABLE_PATH_RESTRICTIONS
unset OVERRIDE_BUILD_DATE BUILD_DATETIME_CHECK
# Android shell helpers are not compatible with nounset.
source build/envsetup.sh
breakfast "$DEVICE" userdebug
product_dir="${OUT_DIR:-out}/target/product/$DEVICE"
shopt -s nullglob
declare -A previous_zips=()
for zip in "$product_dir"/lineage-*.zip; do
    previous_zips["$zip"]=$(stat -c '%y:%s:%i' "$zip")
done
m bacon -j"$JOBS"
fresh_zips=()
for zip in "$product_dir"/lineage-*.zip; do
    if [[ "${previous_zips[$zip]:-}" != "$(stat -c '%y:%s:%i' "$zip")" ]]; then
        fresh_zips+=("$zip")
    fi
done
[[ ${#fresh_zips[@]} -gt 0 ]] || fail "Build returned success but produced no new lineage ZIP in $product_dir."
rsync -a "${fresh_zips[@]}" "$OUTPUT_DIR/"
for image in boot.img dtbo.img vendor_boot.img vbmeta.img recovery.img; do
    [[ ! -f "$product_dir/$image" ]] || rsync -a "$product_dir/$image" "$OUTPUT_DIR/"
done
repo manifest -r -o "$OUTPUT_DIR/source-manifest.xml"
(cd "$OUTPUT_DIR" && sha256sum -- "${fresh_zips[@]##*/}" > SHA256SUMS)
echo "Build complete. Artifacts and source-manifest.xml: $OUTPUT_DIR"
