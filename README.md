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
