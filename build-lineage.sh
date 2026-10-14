#!/usr/bin/env bash
# Shared host/container workflow with isolated Pixel and Realme profiles.
set -Eeo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/bin:$PATH"
export LC_ALL=C
PROFILE=${BUILD_PROFILE:-pixel}
if [[ "${1:-}" == --profile ]]; then
    [[ $# -ge 2 ]] || { echo "--profile needs pixel or realme6" >&2; exit 2; }
    PROFILE=$2
    shift 2
fi
case "$PROFILE" in pixel|realme6) ;; *) echo "Unknown profile: $PROFILE (choose pixel or realme6)" >&2; exit 2 ;; esac
source "$SCRIPT_DIR/profiles/$PROFILE.conf"
BRANCH=${BRANCH:-$PROFILE_BRANCH}
export DEVICE BUILD_PROFILE="$PROFILE"
BUILD_DIR=${BUILD_DIR:-$SCRIPT_DIR/android_source/$PROFILE/$BRANCH}
OUTPUT_DIR=${OUTPUT_DIR:-$SCRIPT_DIR/zips/$PROFILE/$BRANCH}
LOG_DIR=${LOG_DIR:-$SCRIPT_DIR/logs/$PROFILE/$BRANCH}
SYNC_JOBS=${SYNC_JOBS:-4}
SYNC_RETRIES=${SYNC_RETRIES:-3}
SYNC_RETRY_DELAY=${SYNC_RETRY_DELAY:-15}
MIN_FREE_GB=${MIN_FREE_GB:-300}
ACTION=${1:-all}
fail() { echo "ERROR: $*" >&2; exit 1; }
usage() {
    echo "Usage: $0 [--profile pixel|realme6] [check|check-network|sync|build|all]"
    echo "Default profile: pixel. Set BUILD_DIR, OUTPUT_DIR, JOBS, SYNC_JOBS as needed."
}
case "$ACTION" in
    -h|--help) usage; exit 0 ;;
    check|check-network|sync|build|all) ;;
    *) usage; exit 2 ;;
esac
[[ $# -le 1 ]] || fail "Only one action is accepted."
[[ "$BRANCH" == "$PROFILE_BRANCH" ]] || fail "$PROFILE requires $PROFILE_BRANCH; use its matching manifest."
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
LOG_FILE="$LOG_DIR/${PROFILE}-$(date +%Y%m%d-%H%M%S)-$$.log"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'code=$?; echo "ERROR: line $LINENO failed (exit $code). Log: $LOG_FILE" >&2; exit "$code"' ERR
cd "$BUILD_DIR"
python3 "$SCRIPT_DIR/scripts/check_filesystem.py" "$BUILD_DIR"
free_gb=$(df -Pk . | awk 'NR==2 {print int($4/1024/1024)}')
[[ "$ACTION" == check-network || "$free_gb" -ge "$MIN_FREE_GB" ]] || fail "Only ${free_gb} GiB free; require ${MIN_FREE_GB}. For an existing tree, set MIN_FREE_GB to your remaining-space budget."
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
if [[ "$ACTION" == build || "$ACTION" == all ]] && (( mem_kb < 32 * 1024 * 1024 )); then echo "WARNING: Less than 32 GiB RAM available. Soong may require additional RAM/swap even with JOBS=$JOBS."; fi
echo "Profile=$PROFILE Device=$DEVICE Branch=$BRANCH Build=$BUILD_DIR Jobs=$JOBS SyncJobs=$SYNC_JOBS"
echo "Log: $LOG_FILE"
# Refuse old manifests rather than silently mixing or discarding a user's tree.
if [[ -f .lineage-profile ]]; then
    [[ $(cat .lineage-profile) == "$PROFILE" ]] || fail "Source tree belongs to another profile. Use a separate BUILD_DIR."
fi
python3 "$SCRIPT_DIR/scripts/check_manifest.py" "$BUILD_DIR/.repo/local_manifests" "$SCRIPT_DIR/local_manifests/$MANIFEST_NAME"
if [[ -d .repo/manifests/.git ]]; then
    existing_branch=$(git -C .repo/manifests config --get branch.default.merge)
    [[ "$existing_branch" == "refs/heads/$BRANCH" ]] || fail "Existing manifest branch is $existing_branch. Use a separate BUILD_DIR for $BRANCH."
fi
if [[ "$ACTION" == check ]]; then echo "Preflight passed. No source downloaded or compilation started."; exit 0; fi
if [[ "$ACTION" == check-network ]]; then
    python3 "$SCRIPT_DIR/scripts/check_remotes.py" "$SCRIPT_DIR/local_manifests/$MANIFEST_NAME" "$BRANCH"
    exit 0
fi
sync_sources() {
    # .repo may exist after a failed init; always run the idempotent init first.
    echo "Checking manifest and device remote refs before downloading Android sources..."
    python3 "$SCRIPT_DIR/scripts/check_remotes.py" "$SCRIPT_DIR/local_manifests/$MANIFEST_NAME" "$BRANCH"
    echo "Initializing $BRANCH manifest..."
    repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs --no-clone-bundle
    mkdir -p .repo/local_manifests
    cp "$SCRIPT_DIR/local_manifests/$MANIFEST_NAME" ".repo/local_manifests/$MANIFEST_NAME"
    printf '%s\n' "$PROFILE" > .lineage-profile
    local attempt attempt_jobs attempt_log
    local -a sync_status
    # Detect stalled HTTP transfers while retaining the inherited proxy/CA settings.
    export GIT_HTTP_LOW_SPEED_LIMIT=${GIT_HTTP_LOW_SPEED_LIMIT:-1}
    export GIT_HTTP_LOW_SPEED_TIME=${GIT_HTTP_LOW_SPEED_TIME:-120}
    for ((attempt=1; attempt<=SYNC_RETRIES; attempt++)); do
        attempt_jobs=$SYNC_JOBS
        if (( attempt > 1 )); then attempt_jobs=1; fi
        attempt_log="$LOG_DIR/${PROFILE}-sync-$(date +%Y%m%d-%H%M%S)-$$-attempt-$attempt.log"
        echo "Sync attempt $attempt/$SYNC_RETRIES with $attempt_jobs workers; log: $attempt_log"
        if repo sync -c -j"$attempt_jobs" --optimized-fetch --no-clone-bundle --no-tags --fail-fast 2>&1 | tee "$attempt_log"; then
            return 0
        else
            sync_status=("${PIPESTATUS[@]}")
        fi
        [[ ${sync_status[1]} -eq 0 ]] || fail "Cannot write $attempt_log. Check disk space and permissions."
        echo "repo sync exit code: ${sync_status[0]}"
        echo "Sync attempt $attempt/$SYNC_RETRIES failed. Error lines (full context in $attempt_log):"
        grep -Ei -m 20 'error:|fatal:|failed|no space|permission denied' "$attempt_log" || true
        if (( attempt < SYNC_RETRIES )); then sleep "$SYNC_RETRY_DELAY"; fi
    done
    fail "Source sync failed. Fix the first reported repository/network error, then rerun sync."
}
if [[ "$ACTION" == sync || "$ACTION" == all ]]; then sync_sources; fi
if [[ "$ACTION" == sync ]]; then echo "Sync complete."; exit 0; fi
[[ -f build/envsetup.sh ]] || fail "Missing source tree. Run sync first."
python3 "$SCRIPT_DIR/scripts/check_vendor.py" "$BUILD_DIR" "$VENDOR_DIR" "$VENDOR_MAKEFILE"
# Remove inherited workaround flags; use the toolchain shipped with this branch.
unset USE_CCACHE CCACHE_DIR CCACHE_EXEC CC_WRAPPER TEMPORARY_DISABLE_PATH_RESTRICTIONS
unset OVERRIDE_BUILD_DATE BUILD_DATETIME_CHECK
# Android shell helpers are not compatible with nounset.
source build/envsetup.sh
breakfast "$DEVICE" userdebug
product_dir="${OUT_DIR:-out}/target/product/$DEVICE"
shopt -s nullglob
declare -A previous_zips=()
for zip in "$product_dir"/lineage-*-"$DEVICE".zip; do
    previous_zips["$zip"]=$(stat -c '%y:%s:%i' "$zip")
done
m bacon -j"$JOBS"
fresh_zips=()
for zip in "$product_dir"/lineage-*-"$DEVICE".zip; do
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
