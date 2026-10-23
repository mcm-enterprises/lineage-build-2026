# Docker builds for Pixel and Realme 6

Use Docker Engine and Compose v2 on Linux, or Docker Desktop on macOS. The image
uses Ubuntu 22.04 **linux/amd64**, matching the x86_64 Android toolchain. Apple
Silicon runs it through emulation; native ARM64 Android host builds are not provided.
The container user matches the host account's UID/GID.

## Your M4 Mac mini with 16 GB RAM

Start with source sync, not compilation. In Docker Desktop Settings → Resources:

- Allocate around **8–10 GB RAM**, leaving memory for macOS. A full ROM build may
  exceed this even at one build job; a larger x86_64 Linux host is preferable for compilation.
- Set **disk image capacity** high enough for Android sources. Host free space is
  separate from this limit. The default preflight threshold is 200 GiB free inside Docker. This is a
  configurable starting budget, not a measured requirement or guarantee that the
  complete build fits. Usage depends on the source tree and build outputs.
- If your Docker Desktop configuration exposes swap, allow several GB. Swap may
  help memory spikes, but does not guarantee a successful full ROM build.
- Use Docker Desktop's supported amd64/Rosetta emulation option if available for
  the selected VM backend. This repository does not change your Desktop settings.

For the step-by-step connectivity → sync → one-job build workflow, start with
[README](README.md#start-here-docker-desktop-on-your-m4-mac-mini).

The Mac launcher defaults to `sync`, two sync workers and one compile job. It reports Docker's architecture
and assigned memory. This is intentionally independent from your 900 Mbps connection.

```bash
./bootstrap_docker.sh --profile realme6 --action sync
```

After the Realme sync succeeds, you can sync the reference separately:

```bash
./bootstrap_docker.sh --profile pixel --action sync
```

On Linux, the default action is `all`. `--action check`, `check-network`, `sync`,
`build` or `all` overrides the default on either platform. Run one at a time unless
you have enough resources for both. Stop an active build before changing its action.
For example, `JOBS=1 ./bootstrap_docker.sh --profile realme6 --action build` uses
previously synchronized sources. This can be attempted on your existing 16 GB
Mac; a RAM upgrade is not required to try. Compilation is **not verified on Apple Silicon**.

## Storage and ownership

Android source trees use Docker **Linux named volumes**, avoiding macOS shared-folder
case sensitivity and Git checkout performance issues. Logs and artifacts are host bind
mounts for easy access. New source volumes inherit the builder's numeric UID/GID from
the image; no root build or recursive source chown is required.

| Profile | Compose project | Source volume | Host files |
| --- | --- | --- | --- |
| pixel | lineage-pixel | lineage-pixel_source | docker_source/pixel/{zips,logs} |
| realme6 | lineage-realme6 | lineage-realme6_source | docker_source/realme6/{zips,logs} |

Volumes persist after containers stop. `docker compose down` preserves them;
`docker compose down -v` would delete the downloaded sources, so avoid it for normal recovery.
Docker Desktop's disk image must reside on a drive with enough physical space.
If you later change host UID/GID, existing volumes may need an explicit ownership
correction; they are not silently chowned or replaced.

## Monitoring, stages and exit status

The launcher monitors by default and returns the workflow exit code. Use `--detach`
to launch without monitoring. Reattach with `bash monitor_docker.sh --profile realme6`;
it also handles containers that have already stopped. Ctrl+C leaves the
workflow running. Final log lines are repeated to ensure completion output is visible.
Plain `docker compose logs -f` may remain attached after completion and its exit code
is not the workflow result.

Select the profile for every Compose command. For Realme:

```bash
export BUILD_PROFILE=realme6
export HOST_UID=$(id -u) HOST_GID=$(id -g)
bash monitor_docker.sh --profile realme6
docker compose -f docker_env/docker-compose.yml ps -a
container_id=$(docker compose -f docker_env/docker-compose.yml ps -aq lineage-builder)
docker inspect --format 'running={{.State.Running}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' "$container_id"
```

Wait until `running=false` before interpreting the final exit code. A detached
launch only means the container started. A sync exit code zero means
sources synchronized; it does not imply a compiled ZIP. Build success also requires
new artifacts matching the selected target. Full image/phone validation is separate.

Stop only the selected profile with `docker compose -f docker_env/docker-compose.yml stop`.
Rerun the matching launcher to resume. For a foreground stage, stop the active
container first and run:

```bash
export BUILD_PROFILE=realme6
export HOST_UID=$(id -u) HOST_GID=$(id -g)
docker compose -f docker_env/docker-compose.yml run --rm lineage-builder check-network
docker compose -f docker_env/docker-compose.yml run --rm lineage-builder sync
```

Run the launcher at least once to build the image and create host log/output mounts.
For manual `docker compose build`, export HOST_UID/HOST_GID and create the profile's
host zips/logs directories yourself. Existing root-owned bind mounts need correction.
Disk preflight defaults to 200 GiB for fresh sync, 20 GiB for a recognized existing
tree, and 150 GiB for compilation outputs. `MIN_FREE_GB` overrides the selected
budget; `BUILD_MIN_FREE_GB` changes the default compile budget. Lowering a threshold
does not reduce actual storage usage. An `all` run checks compilation space again
after syncing.

## Reusing earlier downloads

Old `docker_source/lineage` and `docker_source/<profile>/lineage` bind directories
remain untouched. The named volumes are separate. To reuse a compatible tree,
first stop the selected container, then copy the old tree into its named volume.
For a matching Pixel 22.1 tree at `docker_source/pixel/lineage`:

```bash
export BUILD_PROFILE=pixel
export HOST_UID=$(id -u) HOST_GID=$(id -g)
docker compose -f docker_env/docker-compose.yml stop
docker compose -f docker_env/docker-compose.yml run --rm --user 0 \
  --volume "$PWD/docker_source/pixel/lineage:/old-source:ro" \
  --entrypoint bash lineage-builder -c 'cp -a /old-source/. /android/lineage/ && chown -R "$1:$2" /android/lineage' -- "$HOST_UID" "$HOST_GID"
```

Only migrate into a new/empty volume, and allow space/time for the copy. This
explicit operation preserves the old tree, uses a read-only old mount and changes
ownership only in the selected source volume. Do not combine branches or devices;
a 23.0 tree cannot become a 22.1 tree by copying it. See [README](README.md).

## Automatic recovery and its limits

The watchdog prints elapsed time, live process count, time without meaningful
activity, and remaining disk every 30 seconds. It observes the command session's
CPU/I/O counters rather than assuming silence means a hang. It terminates the
whole owned process group before retrying, including stuck descendants. No source
files, Git lock files or downloaded repositories are deleted.

| Setting | Default | Meaning |
| --- | --- | --- |
| `SYNC_IDLE_SECONDS` | 600 | Stop a sync with no meaningful process activity |
| `SYNC_MAX_SECONDS` | 43200 | Maximum seconds per sync attempt, even with activity |
| `SYNC_RETRIES` | 3 | Bounded attempts per sync phase; later sync attempts use one worker |
| `SYNC_RETRY_DELAY` | 15 | Seconds between attempts |
| `WATCHDOG_INTERVAL` | 30 | Seconds between heartbeat/resource checks |
| `DISK_RESERVE_GB` | 5 | Runtime reserve in GiB on source, logs and output filesystems |
| `BUILD_IDLE_SECONDS` | 1800 | Maximum idle time during compilation |
| `BUILD_MAX_SECONDS` | 172800 | Maximum seconds for a compile attempt |

Disk exhaustion and log-write errors stop recovery and require intervention.
Compilation is supervised but is not repeatedly rebuilt on failure. Remote checks
and initialization have bounded retries and a 30-minute limit per attempt.
These limits are configurable because emulated toolchains can be slow.

After a host reboot, start Docker Desktop and rerun the same launcher command.
It reuses the source volume and selects the remaining-space budget automatically.
The existing workflow lock file is safe to reuse once the old process is gone.
Automatic host-reboot restart is not enabled: an exhausted retry budget or low-disk
failure must not turn into an endless container restart loop. Stale Git lock errors
are reported for inspection rather than automatically deleting locks.

## Completion and diagnostics

Sync uses `repo sync --verbose` with unbuffered Python output so fetch details
reach the monitor and attempt logs even without an interactive terminal.
Changes to logging apply to the next launched workflow; an existing sync keeps
its original options.

A full successful sync saves `.lineage-sync.json` and a pinned source manifest inside
the source volume. Compilation requires a completed checkpoint for the current
profile/manifest. A failed sync invalidates it; rerun sync to resume preserved
downloads. Older source volumes need one successful sync with the updated script.

Each logged run saves a matching JSON report in `docker_source/<profile>/logs/`.
It includes stage, exit code, RAM/swap availability, free disk and observed cgroup
OOM-counter changes. Exit 137 is reported as possible OOM or forced stop unless
there is stronger counter evidence. A whole-container kill can prevent the final
report update; inspect Docker's `OOMKilled` field as well. No environment variables
or credential values are collected in these reports.

A successful build additionally verifies ZIP CRC integrity and Android OTA device
metadata before exporting artifacts. These checks do not replace phone testing.
The launcher refuses to replace an active container; stop it explicitly first.
