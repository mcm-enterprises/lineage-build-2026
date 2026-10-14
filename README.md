# LineageOS builds: Pixel reference and Realme 6

Choose a build profile. The repository supports assembling both configurations;
full Android compilation and phone boot tests have not been completed here.

| Profile | Phone / build target | Android base | Status |
| --- | --- | --- | --- |
| `pixel` | Pixel 8 Pro / `husky` | LineageOS 22.1 / Android 15 | Reference configuration |
| `realme6` | Realme 6 RMX2001 / `RMX2001L1` | LineageOS 21.0 / Android 14 | Community configuration; compile/boot verification pending |

These are historical releases, not a claim of current security patch coverage.
The Realme target name comes from its community device sources; RMX2001 is the
phone's model number. Vendor fingerprints in that source set reference RMX2002,
so firmware and regional variant compatibility need checking before installation.

## Docker (recommended)

Use Docker Engine and Compose v2 on Linux, or Docker Desktop on macOS.
The container uses `linux/amd64` for the Android toolchain. Run as your regular user:

```bash
# Build the Pixel reference
./bootstrap_docker.sh --profile pixel
BUILD_PROFILE=pixel docker compose -f docker_env/docker-compose.yml logs -f

# Build the Realme 6
./bootstrap_docker.sh --profile realme6
BUILD_PROFILE=realme6 docker compose -f docker_env/docker-compose.yml logs -f
```

Each profile has a separate Compose project (`lineage-pixel`, `lineage-realme6`),
Linux named source volume (`lineage-<profile>_source`), plus logs and output
directories under `docker_source/<profile>/`. Sources are kept inside Docker,
not on the macOS shared filesystem.
The image is shared between profiles for the same host UID/GID. The launcher keeps
your selected Docker context and creates host-owned log/output mounts before starting Docker.
On macOS the launcher defaults to sync only with two workers; use `--action build`
after sync completes if the machine has sufficient resources. On Linux it defaults
to `all`. Explicit `--action` selects a stage on either platform.
See [Docker instructions](README_DOCKER.md) for stages, stopping and exit status.

Budget at least **300 GiB free disk per fresh tree**, preferably on an SSD with a
Linux filesystem, and **32 GiB RAM or more**. Soong may need additional RAM/swap.
Build one profile at a time unless the host has resources for both. Each invocation
sizes its own jobs; it does not divide available RAM between simultaneous builds.

## Native Ubuntu 22.04

```bash
./setup_build_env.sh
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

./build-lineage.sh --profile pixel check
./build-lineage.sh --profile pixel all
./build-lineage.sh --profile realme6 check
./build-lineage.sh --profile realme6 all
```

The default is `pixel`, so existing `./build-lineage.sh all` commands still work.
You can also set `BUILD_PROFILE=realme6`. The command-line profile takes precedence.
`check` validates tools, Git identity, disk budget, profile markers, manifests and filesystem features (case sensitivity, symlinks, execution);
it does not test remote connectivity or download Android sources. `check-network` probes small manifest/device remote refs without the 300 GiB disk requirement. `sync`
checks those refs, then initializes/synchronizes sources. `build` compiles a populated tree. `all` does both.

| Native data | Default path |
| --- | --- |
| Sources | `android_source/<profile>/<branch>/` |
| Artifacts | `zips/<profile>/<branch>/` |
| Logs | `logs/<profile>/<branch>/` |

Overrides: `BUILD_DIR`, `OUTPUT_DIR`, `LOG_DIR`, `JOBS`, `SYNC_JOBS` (default 4),
`SYNC_RETRIES` (default 3) and `MIN_FREE_GB` (default 300). For example:

```bash
BUILD_DIR=/media/BIG_STORAGE/lineageOS/realme6/lineage-21.0 \
  JOBS=4 ./build-lineage.sh --profile realme6 all
```

For a populated tree, set `MIN_FREE_GB` to its remaining-space budget. Build jobs
default to the smaller of CPU count or one per 4 GiB RAM, respecting cgroup v2 limits.
The build runs without ccache. Do not share override directories between profiles.
A persistent profile marker, branch check and exact local manifest check reject
attempts to mix source trees. Unknown profiles or branch overrides are rejected.

Run in the foreground first. To background a build, create the redirect directory
before starting it:

```bash
mkdir -p logs
nohup ./build-lineage.sh --profile realme6 all > logs/realme6-launcher.log 2>&1 &
tail -f logs/realme6-launcher.log
```

## Source configuration

`profiles/*.conf` define the target, base branch and vendor layout.
`local_manifests/husky.xml` selects shusky and its shared Google dependencies,
the upstream 5.15 kernel and matching TheMuppets husky vendor project.
`local_manifests/realme6.xml` pins verified community `lineage-21` snapshots for
RMX2001L1, RM6785-common, kernel, vendor, MediaTek hardware and SELinux policy.
Community branch names differ from the Android base's `lineage-21.0` name.
See [Realme source details](REALME6.md) for upstream links and firmware limitations.

Initialization runs before local-manifest installation. Vendor build files, copy
sources and Git LFS downloads are checked before compilation. The scripts do not
mount factory images, patch blobs by basename, fake the date or change host AppArmor.

Old or extra local manifests are rejected without being deleted. Back them up outside
`.repo/local_manifests`, then remove them from that directory, or use a fresh tree.
Previously built native Pixel trees can be reused with an explicit `BUILD_DIR`; if their
husky manifest matches, the next sync adds the profile marker. Old Docker bind-mounted source directories are preserved and are not automatically
copied into named volumes. See the migration instructions in README_DOCKER.md.

## Outputs and troubleshooting

Success requires a new or updated ZIP ending in the selected device name. ZIPs,
available boot images, `SHA256SUMS` and `source-manifest.xml` are copied into that
profile's output folder; artifacts also stay in the source tree. Verify with
`sha256sum -c SHA256SUMS` in the output folder. This repository does not flash phones.

- **Sync failure:** inspect the first failed project and fix network/disk/authentication
  errors, then rerun `sync`. Partial downloads and locks are preserved; no force-sync. Retries use one worker
  after the first failure and write separate `*-attempt-*.log` files.
- **Missing vendor sources:** rerun sync. For LFS pointers, run `git lfs pull` inside
  the selected vendor directory shown in the error.
- **Killed / exit 137:** inspect kernel logs for OOM, add RAM/swap and reduce JOBS.
- **Sandbox failure:** diagnose the host policy or use the supported Docker environment.
- **Concurrent build:** stop the workflow using that tree. Its file lock does not
  prevent separately invoked repo/build commands, so do not run those alongside it.

Scripts in `archive/` are unsupported historical references. Avoid broad `pkill`
commands or deleting a source tree as a routine sync recovery step.

## Validation

```bash
python3 -m unittest discover -s tests -v
bash -n build-lineage.sh bootstrap_docker.sh setup_build_env.sh docker_env/src/entrypoint.sh
docker compose -f docker_env/docker-compose.yml config --quiet
BUILD_PROFILE=realme6 docker compose -f docker_env/docker-compose.yml config --quiet
```

Offline tests exercise both profiles with mocked Android tools, including isolation,
startup order, retries, locking, vendor checks, failure handling and ZIP export.
CI also builds the Docker image, probes remote refs, smoke-tests both profile entry
points and runs actual repo init for both Android branches. These
checks do not establish that either ROM compiles completely or boots on a phone.
See [original build analysis](BUILD_ANALYSIS.md) for the initial failure findings.
