# LineageOS Build Environment (Pixel 8 Pro)

## 1. Environment Setup (One-Time)
Ensures your Ubuntu host has all required packages, including specific fixes for version 25.10.

```bash
./setup_build_env.sh
```

## 2. Automated Build (Pixel 8 Pro)
We have a unified script `build-lineage2.sh` that handles source initialization, sync, blob rescue (from images), and the final build.

**Key Features:**
*   **Robust Sync:** Automatically detects "unsupported checkout state" errors, deletes the corrupted folder, and retries.
*   **Verbose Logging:** Shows real-time progress of file checks and downloads.
*   **Blob Rescue:** Scans local factory images (in `images/extracted`) to find missing vendor files.

### Usage
The script defaults to **LineageOS 22.1** if no version is specified.

```bash
# Standard Build (Defaults to 22.1)
./build-lineage2.sh

# Build a Specific Version
./build-lineage2.sh 22.2

# Build with Clean (Wipes out/ directory)
./build-lineage2.sh --clean

# Build without Syncing (Faster if source is already updated)
./build-lineage2.sh --skip-sync

# Combine Arguments (Order doesn't matter)
./build-lineage2.sh 22.2 --clean --skip-sync
```

### Setup & blobs
The script expects factory images to be extracted in `images/extracted`. It attempts to "rescue" missing blobs by finding them in that directory if they are missing from the vendor tree.

## 3. Troubleshooting / Hard Reset
If `repo sync` gets stuck or you need to wipe everything:

```bash
# 1. Kill background processes
pkill -f repo
pkill -f python
pkill -f build-lineage

# 2. Wipe the source tree (WARNING: Deletes downloaded source)
rm -rf android_source/LINEAGE_22_1   # or appropriate version folder
```


#### Troubleshooting

Fix broken sync
```
cd /media/BIG_STORAGE/lineage-build-2026/android_source/LINEAGE_23_0

# Remove the broken project references from repo's database
rm -f .repo/project.list
rm -f .repo/.repo_fetchtimes.json

# Delete all traces of these 7 corrupted projects
rm -rf .repo/projects/external/AFLplusplus.git
rm -rf .repo/projects/external/ComputeLibrary.git
rm -rf .repo/projects/device/qcom/sepolicy_vndr
rm -rf .repo/project-objects/external/AFLplusplus.git
rm -rf .repo/project-objects/external/ComputeLibrary.git
rm -rf .repo/project-objects/device/qcom/sepolicy_vndr

# Delete working directories
rm -rf external/AFLplusplus
rm -rf external/ComputeLibrary
rm -rf device/qcom/sepolicy_vndr

# Force repo to rebuild its database and sync fresh
repo sync -c --force-sync --no-clone-bundle --no-tags -j1 \
  external/AFLplusplus \
  external/ComputeLibrary \
  device/qcom/sepolicy_vndr/legacy-um \
  device/qcom/sepolicy_vndr/sm8450 \
  device/qcom/sepolicy_vndr/sm8550 \
  device/qcom/sepolicy_vndr/sm8650 \
  device/qcom/sepolicy_vndr/sm8750
```


```
cd /media/BIG_STORAGE/lineage-build-2026/android_source/LINEAGE_23_0

# Backup the manifest so we don't lose customizations
cp -r .repo/manifests /tmp/manifests_backup 2>/dev/null || true
cp -r .repo/local_manifests /tmp/local_manifests_backup 2>/dev/null || true

# Nuclear option: Delete entire .repo directory
rm -rf .repo

# Reinitialize repo from scratch
repo init -u https://github.com/LineageOS/android.git -b lineage-23.0 --git-lfs --depth=1

# Restore any local manifests if they existed
cp -r /tmp/local_manifests_backup .repo/local_manifests 2>/dev/null || true

# Now sync - this will treat everything as a fresh checkout
repo sync -c -j$(nproc) --force-sync --no-clone-bundle --no-tags
```

### Roms
If the build completes then the output file will be available in a path like this
```
/media/BIG_STORAGE/lineage-build-2026/android_source/LINEAGE_23_1/out/target/product/husky/lineage-23.1-20260107-UNOFFICIAL-husky.zip
```

The file size should be about 800-900MB
