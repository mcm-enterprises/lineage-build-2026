# LineageOS builds: Pixel reference and Realme 6

Sample out image file:
/media/BIG_STORAGE/lineage-build-2026/android/realme6/out/target/product/RMX2001L1/lineage-21.0-20261024-UNOFFICIAL-RMX2001L1.zip

Build automation for two separate devices:

| Profile | Phone / build target | Android base |
| --- | --- | --- |
| `pixel` | Pixel 8 Pro / `husky` | LineageOS 22.1 / Android 15 |
| `realme6` | Realme 6 RMX2001 / `RMX2001L1` | LineageOS 21.0 / Android 14 |

**Status:** the automation and Docker setup pass CI. Remote access and actual
`repo init` have been verified for both profiles. CI also exercises selected source
checkouts; this is smaller than a full source sync. The Realme 6 build completed
successfully on x86_64 Linux on October 24, 2026, including OTA metadata and ZIP
integrity checks. Pixel full builds, Apple Silicon execution and phone boot tests
remain unverified.
These are historical Android releases; current security patch coverage is not claimed.

The Realme profile uses community sources. Its target name is `RMX2001L1`; the phone
model is RMX2001. Its vendor fingerprints reference RMX2002, so firmware and regional
compatibility need checking before installation. See [Realme source details](REALME6.md).

## Install on a Realme 6, or investigate a boot loop

**You do not need Android Studio.** You need `adb` and `fastboot` on the computer
physically connected to the handset by a USB data cable. Run these tools on the
host, outside Docker. If this build machine is remote, copy the artifacts to the
computer beside the phone and install the tools there.

### 1. Understand the warning and preserve your data

An unlocked/not-trusted (orange-state) boot warning is expected with an unlocked
bootloader. It does not, by itself, explain repeated restarts. A phone that keeps
restarting has a separate boot problem to diagnose. **Keep the bootloader unlocked
for this unofficial ROM. Do not relock it to remove the warning.** The build uses
test keys; relocking with incompatible images can prevent booting.

Installing from stock or another ROM requires a clean installation. Formatting
data erases apps, accounts and internal-storage files, including photos. Back up
anything accessible before formatting. If important data is trapped on the looping
phone, stop before the wipe/installation steps and investigate recovery access
first. Charge to at least 50% and use a reliable USB data cable.

### 2. Check compatibility before writing anything

**The October 24 ZIP is compiled and integrity-checked, but has not been tested on
a handset. Do not sideload it until its firmware compatibility has been verified
for your exact phone.** Record these details first:

- The model from the handset/box (this profile targets Realme 6 RMX2001,
  `RMX2001L1`, not Realme 6 Pro or Realme 6i).
- The last working stock build, region and realme UI/Android version, if known.
- What was flashed or changed immediately before the loop, and whether stock or
  custom recovery and fastboot are still accessible.

This is a concrete firmware concern: inspection of this ZIP's
`META-INF/com/google/android/updater-script` shows it writes `preloader_ufs.img`
to `/dev/block/sda` and `/dev/block/sdb`, `lk.img` to both `lk`/`lk2`, and modem,
TEE and other firmware partitions. It also installs boot, vbmeta, DTBO and the
Android logical partitions. It is **not just a system update**. The source's
RMX2002 Android 11 fingerprint is not proof that these firmware images suit an
RMX2001 of any region. Incorrect bootloader/preloader firmware can also break
recovery access. See [source and compatibility details](REALME6.md).

The [community device maintainers' guide](https://realme-mt6785-devs.github.io/RM6785-docs/guides/10_bootloader_unlock/)
uses realme UI 2.0 for its unlock/recovery workflow. That alone does not establish
the correct firmware baseline for this locally built ZIP. Confirm the bundled
firmware and recovery against your exact variant before proceeding past step 4.
Do not guess a stock firmware download, use another model's images, or remove the
installer's device assertion to get past an error.

### 3. Install the USB tools on Ubuntu

For Ubuntu, run these commands yourself on the computer connected to the phone:

```bash
sudo apt update
sudo apt install adb fastboot android-sdk-platform-tools-common
adb version
fastboot --version
```

`android-sdk-platform-tools-common` supplies Linux USB permission rules. If you
get a permissions error, check `id -nG`; if your regular desktop user is not in
`plugdev`, run `sudo usermod -aG plugdev "$USER"`, log out and back in, and reconnect
the cable. Avoid running a second adb server as root.

Google also provides the latest standalone
[SDK Platform-Tools for Linux, macOS and Windows](https://developer.android.com/tools/releases/platform-tools),
without Studio. If using that ZIP instead of Ubuntu's `adb`/`fastboot` packages,
extract it and add its `platform-tools` directory to your PATH. Linux still needs
USB permission rules. See [Google's Ubuntu USB setup](https://developer.android.com/studio/run/device).

### 4. Get out of the loop and identify the available mode

Realme documents holding **Power + Volume Up for at least eight seconds** to
force a restart. From power-off, hold **Power + Volume Down** to enter recovery.
During a loop, switch to that recovery combination when the screen goes black.
See [Realme's recovery/restart instructions](https://www.realme.com/global/support/troubleshooting).
Entering recovery does not itself erase data; do not select a wipe yet.

For bootloader fastboot, the community guide says to start powered off and hold
**all three buttons** until fastboot appears. Connect only this phone, then check:

```bash
adb devices -l
fastboot devices
```

Only the tool matching the phone's current mode should detect it. An empty adb
list while in fastboot is expected. Android USB debugging is not needed for
bootloader fastboot or recovery's explicit ADB sideload mode. `unauthorized` in a
running Android system means that computer has not been approved there.

In fastboot, these commands query information without flashing:

```bash
fastboot getvar product
fastboot getvar unlocked
fastboot getvar is-userspace
```

Some bootloaders do not implement every query. An unknown-variable response is
not confirmation of model or unlock status. `is-userspace: yes` means fastbootd;
select reboot to bootloader before using the recovery-flash command below.
Cross-check the physical model; a common board name is not sufficient proof.
If neither tool sees the phone, try another data cable/USB port and check USB
permissions. If neither recovery nor fastboot can be reached, stop here: this
guide cannot supply a verified low-level unbrick procedure. Use Realme support
or a device maintainer with the exact model and previous firmware details.

### 5. Verify the local artifacts

On this build machine, the exported artifacts are here:

```bash
cd /media/BIG_STORAGE/lineage-build-2026/docker_source/realme6/zips
sha256sum -c SHA256SUMS
ls -lh lineage-21.0-20261024-UNOFFICIAL-RMX2001L1.zip recovery.img
```

Require the ZIP checksum to report `OK`. This build's `SHA256SUMS` covers the ROM
ZIP, not the separate images. When copying `recovery.img` to another computer,
compare `sha256sum recovery.img` on both computers as well. Integrity checks do
not prove hardware compatibility. Keep the ZIP and recovery from the same build;
later builds can replace the contents of this export directory.

### 6. Install recovery, then clean-install the ZIP (conditional)

**Only proceed after step 2's firmware/recovery compatibility is established,
the bootloader is confirmed unlocked, and you accept losing the phone's data.**
These are manual instructions, not a flashing script. Check each command's result
before continuing. Use the artifact directory from step 5, or the directory where
you copied those files on the USB-connected computer.

With the phone in bootloader fastboot, install the matching `recovery.img`:

```bash
fastboot flash recovery recovery.img
fastboot reboot recovery
```

Require the flash to finish with `OKAY`. If reboot-to-recovery is unsupported,
enter recovery with the hardware buttons. Go straight to recovery: booting stock
Android in between can restore stock recovery. If matching Lineage Recovery is
already installed, enter it directly. If recovery fails to boot, stop and check
firmware compatibility rather than flashing random vbmeta/boot images.

In **Lineage Recovery**, for a first installation from stock or another ROM:

1. Select **Factory reset → Format data/factory reset** and confirm. This erases
   user data/internal storage. If formatting fails, stop and record the error.
2. Return to the main menu and choose **Apply update → Apply from ADB**.
3. On the computer, run `adb devices`; require exactly one phone in `sideload`
   mode, then run:

   ```bash
   adb -d sideload lineage-21.0-20261024-UNOFFICIAL-RMX2001L1.zip
   ```

4. Require recovery to report successful installation. If it reports a device
   mismatch, partition/firmware error or signature failure, stop and investigate;
   do not bypass checks by editing the ZIP. A matching locally built recovery
   should trust its matching build's signing key. A different recovery can reject
   this unofficial package even though its checksum is correct.
5. Choose **Reboot system now** after success. Allow roughly 10–15 minutes for
   the first boot. A continuing cycle of restarts is a failure, not normal setup.

This build supports both ext4 and f2fs for userdata; the built recovery's factory
reset is the route described here. Other recoveries have different menus; follow
the [maintainers' installation guide](https://realme-mt6785-devs.github.io/RM6785-docs/guides/27_installing_roms/)
for those, including matching recovery to the firmware version. Do not wipe
system/vendor or manually erase preloader, nvram, nvdata, persist or other
calibration/firmware partitions. The OTA installer handles its own partitions;
do not separately flash every exported `.img` or use `fastboot update` on this
recovery-installable ZIP. Start with the base ROM before adding Google apps or root.

### 7. If installation fails or it still loops

Record the full recovery error before retrying. In recovery's normal ADB mode
(leave sideload mode first), if shell access is available, save its log:

```bash
adb -d pull /tmp/recovery.log ./realme6-recovery.log
```

If Android starts far enough to expose an already-authorized adb connection,
`adb -d logcat -b all -d > realme6-boot.log` may capture the failure. Failure to
connect is not a reason to wipe more partitions. With important data already
backed up, a confirmed compatible clean installation that still loops needs
device debugging or restoration of the exact model/region's stock firmware using
its supported procedure. Keep the bootloader unlocked during custom-ROM recovery.
The warning itself is explained by [Android's Verified Boot documentation](https://source.android.com/docs/security/features/verifiedboot/boot-flow).

## Get the updated workflow

While [PR #1](https://github.com/mcm-enterprises/lineage-build-2026/pull/1) is unmerged,
use its branch. For a fresh checkout:

```bash
git clone --branch codex/fix-husky-build-workflow https://github.com/mcm-enterprises/lineage-build-2026.git
cd lineage-build-2026
```

If you already have a checkout, fetch and switch to that branch after preserving
any local changes. The original `main` does not yet contain this workflow.

## Start here: Docker Desktop on your M4 Mac mini

Ubuntu remains the build environment. Docker uses `linux/amd64`, so your M4 runs
these tools through emulation. A macOS container would not replace the Linux
Android toolchain.

Your 16 GB Mac can attempt source sync and a conservative build. More RAM makes
compilation easier, but buying a 64 GB machine is not a prerequisite to trying.
Full builds may be slow or run out of memory, even with one build job.

Before starting, open **Docker Desktop → Settings → Resources**:

- Allocate about **8–10 GB RAM**, leaving memory for macOS.
- Keep at least **200 GiB free on the host filesystem** containing this project for
  a fresh source tree. On macOS, the project folder must also be shared with Docker
  Desktop and stored on a case-sensitive filesystem. Allow more space if keeping
  both profiles.
- Allow several GB of swap if your Desktop configuration offers it.
- Enable the supported amd64/Rosetta option if available for your VM backend.

These settings are not changed by the scripts. Run one profile at a time.
Detailed storage and migration guidance is in [Docker instructions](README_DOCKER.md).

### 1. Check connectivity

From the repository root, with Docker Desktop running:

```bash
./bootstrap_docker.sh --profile realme6 --action check-network
```

This builds the Ubuntu image, checks the source filesystem and probes small remote
refs. It does not download the full Android tree and skips the fresh-tree disk budget.
The launcher streams logs, prints SUCCESS or FAILED, and returns the workflow exit
code. Ctrl+C leaves the container running. Use `--detach` to start without monitoring.

### 2. Sync sources

After the check finishes successfully:

```bash
./bootstrap_docker.sh --profile realme6 --action sync
```

Downloads persist under `android/<profile>/` in the project. Partial downloads
survive failed attempts.
The Mac launcher uses two sync workers and defaults to one compile job; after a failure, retries use one worker.
The first sync is a large download; your connection speed alone does not determine
how quickly thousands of Git repositories fetch and check out.

To run the full sync, compile and artifact checks in one command on Linux:

```bash
./bootstrap_docker.sh --profile realme6 --action all
```

The launcher monitors the run and returns its final exit status. Reattach to a
running or completed workflow with `bash monitor_docker.sh --profile realme6`.

### 3. Confirm the stage finished

```bash
container_id=$(BUILD_PROFILE=realme6 docker compose -f docker_env/docker-compose.yml ps -aq lineage-builder)
docker inspect --format 'running={{.State.Running}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' "$container_id"
```

Wait for `running=false`. Then `exit=0` means that stage succeeded. Successful sync
means sources are ready for a build attempt; it does not mean a ROM has compiled.
A detached launch message alone does not mean success.

### 4. Attempt a one-job build

Once sync has succeeded:

```bash
JOBS=1 ./bootstrap_docker.sh --profile realme6 --action build
```

The `build` stage requires a completed-sync checkpoint matching the profile and
manifest. A failed or interrupted sync must be rerun successfully before compilation.
Existing downloads are reused. The stage then uses the downloaded tree. Check its final exit status as above.
If it succeeds, ZIPs and checksums appear in `docker_source/realme6/zips/`.
Compilation checks for 150 GiB remaining before starting, including after `all`
finishes syncing. This is a configurable budget, not a measured requirement for this
device. `MIN_FREE_GB` overrides the preflight budget; `BUILD_MIN_FREE_GB` changes
only the default compilation budget.

For the Pixel reference, repeat these stages with `--profile pixel` and
`BUILD_PROFILE=pixel`. Its artifacts are in `docker_source/pixel/zips/`.
Do not run both profiles together on the 16 GB Mac.

## Actions and defaults

| Action | What it does |
| --- | --- |
| `check` | Tools, Git identity, filesystem, disk budget and source-profile checks |
| `check-network` | The same preparation plus small remote-ref probes; skips the 200 GiB budget |
| `sync` | Remote probes, repo initialization and source synchronization |
| `build` | Vendor checks, compilation and artifact export from an existing tree |
| `validate` | Vendor firmware checks, SELinux and framework/vendor HAL validation without a full ROM build |
| `all` | Sync, then build |

The `all` workflow runs the source checks, syncs or resumes repositories, compiles
the ROM, then validates and exports the ZIP and checksums.

The Docker launcher defaults to **sync on macOS**. On Linux it resumes an
incremental **build** from a valid completed-sync checkpoint, or runs **all** when
sync is still needed. After fixing a compilation error, rerun the launcher to
reuse completed outputs and continue. Explicit `--action all` syncs again.
Use explicit
`--action` arguments to make your intent clear. Native `build-lineage.sh` defaults
to `all`. The default profile is `pixel`; `--profile` overrides `BUILD_PROFILE`.
Stop an active container before changing its action. The launcher refuses to
replace a running workflow, preserving ongoing sync/build work.

Profiles have separate Compose projects, source folders, logs and output folders.
A source profile marker, branch check and exact local-manifest check reject mixed trees.
Unknown profiles and mismatched branch overrides are rejected.

## Logs, stopping and recovery

Docker logs are also saved under `docker_source/<profile>/logs/`, including a log
for each sync attempt. Matching `.json` run reports record the last stage, exit code,
RAM/swap snapshots and cgroup OOM-counter changes. If the entire container is killed,
the report may contain only its start snapshot; also check Docker's `OOMKilled` flag. To stop the Realme workflow:

```bash
BUILD_PROFILE=realme6 docker compose -f docker_env/docker-compose.yml stop
```

After a reboot, start Docker Desktop and rerun the same launcher/action to resume.
Source folders persist. Containers do not automatically restart after a host reboot;
failed stages are not retried forever. The scripts never delete a source tree, remove
Git locks or force-sync as an automatic recovery.

- **Sync hang or failure:** the watchdog stops the command group after 10 minutes
  without meaningful CPU/I/O activity or a 12-hour attempt deadline, then retries.
  Initialization and remote checks also get bounded retries. Sync defaults to three
  attempts, with one worker after the first failure. If all attempts fail, it exits
  clearly; inspect the attempt log and rerun after resolving the cause.
- **Low disk:** a 5 GiB runtime reserve is checked every 30 seconds. The workflow
  stops and preserves downloads instead of retrying into a full filesystem.
  Free space or expand storage before resuming. The reserve is a sampled guard,
  not a guarantee against a large write filling the disk between checks.
- **Quiet compilation:** CPU/I/O activity keeps it running; a 30-minute idle limit
  and 48-hour deadline bound a hung compile. Compilation failures are reported
  rather than automatically rebuilding repeatedly.
- **Killed / exit 137:** often memory pressure, but also possible after a forced stop.
  `oom=true` confirms a container OOM kill. `oom=false` does not rule out a compiler
  process being killed inside Docker's VM. Check the surrounding log and Desktop
  memory usage; reduce JOBS and use available swap.
- **Missing vendor files / LFS pointers:** rerun sync. If instructed, run `git lfs pull`
  inside the selected vendor checkout in the container, not the host repository.
- **Filesystem check failure:** inspect mount permissions/noexec and use a
  case-sensitive filesystem for Android sources on macOS.
- **Profile/manifest conflict:** preserve the old tree or manifest, then use the
  matching profile or a separate source directory. Do not combine branches/devices.

## Native Ubuntu 22.04 alternative

Run natively on x86_64 Ubuntu 22.04, not directly in macOS Terminal:

```bash
./setup_build_env.sh
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
./build-lineage.sh --profile realme6 check-network
./build-lineage.sh --profile realme6 sync
JOBS=1 ./build-lineage.sh --profile realme6 build
```

| Native data | Default path |
| --- | --- |
| Sources | `android_source/<profile>/<branch>/` |
| Artifacts | `zips/<profile>/<branch>/` |
| Logs | `logs/<profile>/<branch>/` |

Overrides: `BUILD_DIR`, `OUTPUT_DIR`, `LOG_DIR`, `JOBS`, `SYNC_JOBS`, `SYNC_RETRIES`
(default 3) and `MIN_FREE_GB` (automatic: 200 GiB for a fresh sync, 20 GiB to
resume a recognized tree, 150 GiB for compilation). These are starting budgets,
not guarantees the whole build fits. Build jobs normally use the smaller of
CPU count or one per 4 GiB RAM, respecting cgroup v2 limits. Ccache is disabled.
Do not share override directories between profiles. More RAM, such as 32 GiB or more,
is recommended for compilation, not enforced as a hard prerequisite.

## Source configuration and outputs

`profiles/*.conf` select targets, branches and vendor layouts. The Pixel manifest
uses shusky, its Google dependencies and TheMuppets husky blobs. The Realme manifest
pins community device/common/kernel/vendor/MediaTek dependencies. See
[Realme revisions](REALME6.md) and [build analysis](BUILD_ANALYSIS.md).

Build success requires a new or updated ZIP ending in the selected device name.
Before export, every ZIP is checked for readable Android OTA metadata, the expected
`pre-device` target and CRC integrity; a matching filename alone is insufficient.
Available boot images, `SHA256SUMS` and a pinned `source-manifest.xml` are exported
alongside the ZIP. Verify with `sha256sum -c SHA256SUMS` in the output directory.
These scripts do not flash a phone. A successful compile still needs device testing.

Old scripts in `archive/` are unsupported references. Existing native trees may be
reused with a matching explicit BUILD_DIR. Old Docker bind-mounted source trees
remain untouched; [migration instructions](README_DOCKER.md#reusing-earlier-downloads)
explain how to copy a compatible tree into the matching `android/<profile>/` folder.

## Validation

Automated checks cover Docker image builds, both profile entry points, real remote-ref
probes, actual repo init plus selected Android/device checkouts for both branches,
and named-volume ownership with UID/GID 501:20. Tests also cover interrupted-sync
recovery, OTA validation, active-workflow protection and memory reports. CI runs on x86_64 Linux; it does not test your M4 or a full Android build.
To run the local checks:

```bash
python3 -m unittest discover -s tests -v
bash -n build-lineage.sh bootstrap_docker.sh monitor_docker.sh setup_build_env.sh docker_env/src/entrypoint.sh
docker compose -f docker_env/docker-compose.yml config --quiet
BUILD_PROFILE=realme6 docker compose -f docker_env/docker-compose.yml config --quiet
```
