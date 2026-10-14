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
  separate from this limit. Budget 300 GiB free inside Docker per fresh tree;
  roughly 400 GB capacity for one profile or 700–800 GB for two is a starting point,
  subject to actual use and available host storage.
- If your Docker Desktop configuration exposes swap, allow several GB. Swap may
  help memory spikes, but does not guarantee a successful full ROM build.
- Use Docker Desktop's supported amd64/Rosetta emulation option if available for
  the selected VM backend. This repository does not change your Desktop settings.

For the step-by-step connectivity → sync → one-job build workflow, start with
[README](README.md#start-here-docker-desktop-on-your-m4-mac-mini).

The Mac launcher defaults to `sync` and two workers. It reports Docker's architecture
and assigned memory. This is intentionally independent from your 900 Mbps connection.

```bash
./bootstrap_docker.sh --profile realme6 --action sync
BUILD_PROFILE=realme6 docker compose -f docker_env/docker-compose.yml logs -f
```

After the Realme sync succeeds, you can sync the reference separately:

```bash
./bootstrap_docker.sh --profile pixel --action sync
BUILD_PROFILE=pixel docker compose -f docker_env/docker-compose.yml logs -f
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

Select the profile for every Compose command. For Realme:

```bash
export BUILD_PROFILE=realme6
export HOST_UID=$(id -u) HOST_GID=$(id -g)
docker compose -f docker_env/docker-compose.yml logs -f
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
A populated source tree can use a smaller remaining-space threshold, e.g. MIN_FREE_GB=100.

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
