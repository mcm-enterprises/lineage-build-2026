# LineageOS 22.1 for Pixel 8 Pro (husky)

This repository automates source synchronization and an unofficial `userdebug` build.
The supported combination is **husky + lineage-22.1 (Android 15)**. This is a historical
release, not a claim that 22.1 has current security patches. Other releases need a
separately verified manifest and their own source directory.

Use Ubuntu 22.04 x86_64, or the Ubuntu 22.04 Docker image on another Linux host.
Plan for at least **300 GiB free disk**, preferably on an SSD with a Linux filesystem,
and **32 GiB RAM or more**. Soong can need substantially more memory; low parallelism
alone does not guarantee it will fit. Use swap if needed. Avoid FAT/exFAT source drives.

## Recommended: Docker

Install Docker Engine and Compose v2, then run from your regular account:

```bash
./bootstrap_docker.sh
docker compose -f docker_env/docker-compose.yml logs -f
```

The launcher creates host-owned directories and builds the container user with your
UID/GID. It respects your selected Docker context. See [Docker instructions](README_DOCKER.md)
for checking exit status, stopping, and resuming.

## Native Ubuntu 22.04

```bash
./setup_build_env.sh
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
./build-lineage.sh check
./build-lineage.sh all
```

`check` checks tools, identity, disk budget and conflicting local manifests; it does
not test remote connectivity or download Android sources. `sync` only initializes
and synchronizes sources. `build` uses the existing tree and does not run the full
sync step. `all` performs both. Each invocation writes its own log in `logs/`.

To use an existing source drive or reduce parallelism:

```bash
BUILD_DIR=/media/BIG_STORAGE/lineageOS/android_source/LINEAGE_22_1 \
  JOBS=4 SYNC_JOBS=4 ./build-lineage.sh all
```

Run in the foreground first so errors are visible. For a background build, create
the redirect directory **before** starting (shell redirection runs before the script):

```bash
mkdir -p logs
nohup ./build-lineage.sh all > logs/launcher.log 2>&1 &
echo $! > logs/launcher.pid
tail -f logs/launcher.log
```

Defaults: source `android_source/LINEAGE_22_1`, artifacts `zips/`, logs `logs/`, sync
parallelism 4, sync retries 3. Build jobs default to the smaller of CPU count or one
job per 4 GiB RAM (including the cgroup v2 limit). Override `JOBS`, `SYNC_JOBS`,
`SYNC_RETRIES`, `OUTPUT_DIR`, `LOG_DIR`, or `MIN_FREE_GB` as needed. For a populated
tree, set `MIN_FREE_GB` to your remaining-space budget rather than the fresh-tree 300 GiB.
The build runs without ccache by default.

## Source and vendor handling

`local_manifests/husky.xml` uses the shared `device/google/shusky` tree, its zuma,
gs101 and gs-common dependencies, and the upstream shusky 5.15 kernel remote.
Only the matching TheMuppets husky vendor repository is needed for this device.
`repo init --git-lfs` runs before installing the local manifest. Missing vendor
copy sources and LFS pointer files are checked before compiling.

The script never patches blobs by searching for filenames, fakes the build date,
or changes host AppArmor settings. These workarounds can hide the actual mismatch.
If you choose to extract blobs yourself, use the branch's
`device/google/shusky/husky/extract-files.py` and matching firmware from the
[LineageOS device guide](https://wiki.lineageos.org/devices/husky/build/), rather than
copying similarly named files from an arbitrary factory image.

Existing `muppets.xml`, the old `husky.xml`, or another Google local manifest may
conflict. The script stops and identifies the file: back it up outside
`.repo/local_manifests`, then remove it from that directory or use a fresh BUILD_DIR.
A tree initialized on another branch is rejected. Your source tree is never deleted.

## Outputs and diagnosing failures

Success requires a new or updated `lineage-*.zip`, which is copied to `zips/` alongside
available boot images, `SHA256SUMS`, and a revision-pinned `source-manifest.xml`.
Artifacts remain in the source tree too. Verify with `sha256sum -c SHA256SUMS` in the
output directory. Installation requires the device-specific LineageOS instructions;
this repository does not flash your phone.

- **Sync failure:** read the first failed project in the log, fix network/disk/authentication
  errors and rerun `sync`. Retries preserve partial downloads. No locks are deleted and
  `--force-sync` is not used.
- **Missing vendor files/LFS pointers:** rerun sync; for pointers, run
  `git -C "$BUILD_DIR/vendor/google/husky" lfs pull` with BUILD_DIR set to your source tree.
- **Killed / exit 137:** inspect host kernel logs for an OOM kill, add RAM/swap and reduce JOBS.
- **Sandbox/user namespace error:** prefer the supported Ubuntu/Docker environment and
  diagnose the specific host policy instead of globally disabling security controls.
- **Concurrent build:** stop the workflow using that source tree before restarting.
  A file lock prevents two copies of this script from running against one tree; avoid
  separately running repo or builds in that tree while the workflow is active.

The old scripts in `archive/` are retained for reference and are not supported entry points.
Do not use broad `pkill -f python/repo` commands or delete the entire tree to fix a sync error.

## Validation

```bash
python3 -m unittest discover -s tests -v
bash -n build-lineage.sh bootstrap_docker.sh setup_build_env.sh docker_env/src/entrypoint.sh
docker compose -f docker_env/docker-compose.yml config --quiet
```

Offline integration tests use mocked Android tools to cover startup order, retries,
locking, branch/manifest conflicts, vendor validation, error propagation and artifact
export. They do not prove that a complete Android image compiles or boots. CI also
builds the Docker image and checks its tools; a full build needs a suitably sized host.
See [analysis and changes](BUILD_ANALYSIS.md) for the original failure findings.
