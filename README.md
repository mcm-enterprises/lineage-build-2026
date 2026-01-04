# LineageOS Build Environment (Pixel 8 Pro)

## 1. Environment Setup (One-Time)
Ensures your Ubuntu host has all required packages, including specific fixes for version 25.10.

```bash
./setup_build_env.sh
```

## 2. Automated Build (Pixel 8 Pro)
We have a unified script that handles `repo init`, `sync`, vendor blobs (via TheMuppets), and the final build.

```bash
# Run in background (recommended due to long run time)
nohup ./build-husky-baremetal.sh > logs/husky_build.log 2>&1 &

# Monitor progress
tail -f logs/husky_build.log
```

**Configuration:**
*   **Device:** Google Pixel 8 Pro (`husky`)
*   **Target:** LineageOS 22.1 (Android 15 Stable)
*   **Source Tree:** `android_source/LINEAGE_22_1`
*   **Logs:** `logs/husky_22_1.log`
*   **Output:** `zips/`

## 3. Hard Reset (If Build Fails/Corrupts)
If `repo sync` gets stuck or corrupted (common on external drives), use this Nuclear Option to start fresh.

**WARNING: Deletes 100GB of source code!**

```bash
# 1. Kill EVERY background process
pkill -f repo
pkill -f python
pkill -f build-husky

# 2. Verify cleaning path (Safety Check)
cd /media/BIG_STORAGE/lineageOS/android_source

# 3. Wipe the specific version folder
rm -rf LINEAGE_23_0

# 4. Restart the build script
cd ..
nohup ./build-husky-baremetal.sh > logs/husky_build.log 2>&1 &
```

### Monitoring the Build
The script runs in the background. Check logs with:
```bash
tail -f logs/husky_22_1.log
```
(Note: Log filename varies, check `logs/` directory).

### Stopping the Build
To forcefully stop the background build process:
```bash
pkill -f build-husky-baremetal.sh
```
*Note: The script now includes a check to prevent multiple instances from running simultaneously.*
