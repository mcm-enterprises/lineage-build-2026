# LineageOS builds: Pixel reference and Realme 6

Build automation for two separate devices:

| Profile | Phone / build target | Android base |
| --- | --- | --- |
| `pixel` | Pixel 8 Pro / `husky` | LineageOS 22.1 / Android 15 |
| `realme6` | Realme 6 RMX2001 / `RMX2001L1` | LineageOS 21.0 / Android 14 |

**Status:** the automation and Docker setup pass CI. Remote access and actual
`repo init` have been verified for both profiles. Full Android source sync, ROM
compilation, Apple Silicon execution and phone boot tests remain unverified.
These are historical Android releases; current security patch coverage is not claimed.

The Realme profile uses community sources. Its target name is `RMX2001L1`; the phone
model is RMX2001. Its vendor fingerprints reference RMX2002, so firmware and regional
compatibility need checking before installation. See [Realme source details](REALME6.md).

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
- Increase Docker's **disk image capacity** so there is at least **300 GiB free
  inside Docker** for a fresh source tree. Host free space and Docker capacity differ.
  Allow additional capacity if keeping both profiles.
- Allow several GB of swap if your Desktop configuration offers it.
- Enable the supported amd64/Rosetta option if available for your VM backend.

These settings are not changed by the scripts. Run one profile at a time.
Detailed storage and migration guidance is in [Docker instructions](README_DOCKER.md).

### 1. Check connectivity

From the repository root, with Docker Desktop running:

```bash
./bootstrap_docker.sh --profile realme6 --action check-network
BUILD_PROFILE=realme6 docker compose -f docker_env/docker-compose.yml logs -f
```

This builds the Ubuntu image, checks the source filesystem and probes small remote
refs. It does not download the full Android tree and skips the fresh-tree disk budget.
Press Ctrl+C to leave the log viewer; that does not stop the container.

### 2. Sync sources

After the check finishes successfully:

```bash
./bootstrap_docker.sh --profile realme6 --action sync
BUILD_PROFILE=realme6 docker compose -f docker_env/docker-compose.yml logs -f
```

Downloads persist in a Linux named volume. Partial downloads survive failed attempts.
The Mac launcher uses two sync workers; after a failure, retries use one worker.
The first sync is a large download; your connection speed alone does not determine
how quickly thousands of Git repositories fetch and check out.

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
BUILD_PROFILE=realme6 docker compose -f docker_env/docker-compose.yml logs -f
```

The `build` stage uses the downloaded tree. Check its final exit status as above.
If it succeeds, ZIPs and checksums appear in `docker_source/realme6/zips/`.
If the populated tree has less than the default 300 GiB remaining, set `MIN_FREE_GB`
to an appropriate remaining-space budget; that check is conservative, not a measured
requirement for every incremental build.

For the Pixel reference, repeat these stages with `--profile pixel` and
`BUILD_PROFILE=pixel`. Its artifacts are in `docker_source/pixel/zips/`.
Do not run both profiles together on the 16 GB Mac.

## Actions and defaults

| Action | What it does |
| --- | --- |
| `check` | Tools, Git identity, filesystem, disk budget and source-profile checks |
| `check-network` | The same preparation plus small remote-ref probes; skips the 300 GiB budget |
| `sync` | Remote probes, repo initialization and source synchronization |
| `build` | Vendor checks, compilation and artifact export from an existing tree |
| `all` | Sync, then build |

The Docker launcher defaults to **sync on macOS** and **all on Linux**. Use explicit
`--action` arguments to make your intent clear. Native `build-lineage.sh` defaults
to `all`. The default profile is `pixel`; `--profile` overrides `BUILD_PROFILE`.
Stop an active container before changing its action.

Profiles have separate Compose projects, source volumes, logs and output folders.
A source profile marker, branch check and exact local-manifest check reject mixed trees.
Unknown profiles and mismatched branch overrides are rejected.

## Logs, stopping and recovery

Docker logs are also saved under `docker_source/<profile>/logs/`, including a log
for each sync attempt. To stop the Realme workflow:

```bash
BUILD_PROFILE=realme6 docker compose -f docker_env/docker-compose.yml stop
```

Rerun the same launcher/action to resume. Source volumes persist. Avoid
`docker compose down -v`: it deletes the downloaded source volume. The scripts
never delete a source tree, remove Git locks or force-sync as an automatic recovery.

- **Sync failure:** inspect the first failed project in the attempt log, resolve
  its network/disk/permission error and rerun `sync`.
- **Killed / exit 137:** often memory pressure, but also possible after a forced stop.
  `oom=true` confirms a container OOM kill. `oom=false` does not rule out a compiler
  process being killed inside Docker's VM. Check the surrounding log and Desktop
  memory usage; reduce JOBS and use available swap.
- **Missing vendor files / LFS pointers:** rerun sync. If instructed, run `git lfs pull`
  inside the selected vendor checkout in the container, not the host repository.
- **Filesystem check failure:** inspect mount permissions/noexec and use the Linux
  named source volume. Do not use a case-insensitive macOS folder for Android sources.
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
(default 3) and `MIN_FREE_GB` (default 300). Build jobs normally use the smaller of
CPU count or one per 4 GiB RAM, respecting cgroup v2 limits. Ccache is disabled.
Do not share override directories between profiles. More RAM, such as 32 GiB or more,
is recommended for compilation, not enforced as a hard prerequisite.

## Source configuration and outputs

`profiles/*.conf` select targets, branches and vendor layouts. The Pixel manifest
uses shusky, its Google dependencies and TheMuppets husky blobs. The Realme manifest
pins community device/common/kernel/vendor/MediaTek dependencies. See
[Realme revisions](REALME6.md) and [build analysis](BUILD_ANALYSIS.md).

Build success requires a new or updated ZIP ending in the selected device name.
Available boot images, `SHA256SUMS` and a pinned `source-manifest.xml` are exported
alongside the ZIP. Verify with `sha256sum -c SHA256SUMS` in the output directory.
These scripts do not flash a phone. A successful compile still needs device testing.

Old scripts in `archive/` are unsupported references. Existing native trees may be
reused with a matching explicit BUILD_DIR. Old Docker bind-mounted source trees
remain untouched; [migration instructions](README_DOCKER.md#reusing-earlier-downloads)
explain how to copy a compatible tree into a new named volume.

## Validation

CI passes 22 tests, Docker image builds, both profile entry points, real remote-ref
probes, actual repo init for both branches, and named-volume ownership with UID/GID
501:20. CI runs on x86_64 Linux; it does not test your M4 or a full Android build.
To run the local checks:

```bash
python3 -m unittest discover -s tests -v
bash -n build-lineage.sh bootstrap_docker.sh setup_build_env.sh docker_env/src/entrypoint.sh
docker compose -f docker_env/docker-compose.yml config --quiet
BUILD_PROFILE=realme6 docker compose -f docker_env/docker-compose.yml config --quiet
```
