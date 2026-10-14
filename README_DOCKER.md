# Docker builds for Pixel and Realme 6

Use Docker Engine and Compose v2 on x86_64 Linux. Budget 300 GiB free disk per fresh
source tree and preferably 32 GiB or more RAM. The Ubuntu 22.04 container runs as
an unprivileged user with the host account's UID/GID.

```bash
./bootstrap_docker.sh --profile pixel
./bootstrap_docker.sh --profile realme6
```

Run one at a time unless you have enough RAM and disk for both. Select the profile
for every Compose command. For example, the Realme build:

```bash
export BUILD_PROFILE=realme6
export HOST_UID=$(id -u) HOST_GID=$(id -g)
docker compose -f docker_env/docker-compose.yml logs -f
docker compose -f docker_env/docker-compose.yml ps -a
container_id=$(docker compose -f docker_env/docker-compose.yml ps -aq lineage-builder)
docker inspect --format '{{.State.ExitCode}}' "$container_id"
```

The default profile is `pixel`. `BUILD_PROFILE` selects distinct Compose projects
and persistent directories:

| Profile | Project | Host data |
| --- | --- | --- |
| pixel | lineage-pixel | docker_source/pixel/{lineage,zips,logs} |
| realme6 | lineage-realme6 | docker_source/realme6/{lineage,zips,logs} |

A detached launch only means the container started. Exit code zero and newly
exported artifacts indicate workflow success. Full image/phone validation is separate.

Stop the selected build with `docker compose -f docker_env/docker-compose.yml stop`.
Rerun the matching launcher command to resume; sources persist. Stages can run in
the foreground after stopping any active build using that profile:

```bash
export BUILD_PROFILE=realme6
export HOST_UID=$(id -u) HOST_GID=$(id -g)
docker compose -f docker_env/docker-compose.yml run --rm lineage-builder check
docker compose -f docker_env/docker-compose.yml run --rm lineage-builder check-network
docker compose -f docker_env/docker-compose.yml run --rm lineage-builder sync
docker compose -f docker_env/docker-compose.yml run --rm lineage-builder build
```

The launcher creates writable host mounts and builds the image. For manual image
builds, export HOST_UID/HOST_GID before `docker compose build` and create all three
host directories yourself. Existing root-owned mounts need ownership correction.

Tune jobs with `JOBS=4 SYNC_JOBS=4 ./bootstrap_docker.sh --profile realme6`.
For a populated tree, adjust the remaining-space threshold with `MIN_FREE_GB=100`.
The image has no arbitrary 24 GiB memory cap and does not globally switch contexts.

Old `docker_source/lineage` trees are not migrated automatically. Back up/move a
compatible 22.1 Pixel tree into `docker_source/pixel/lineage`; a 23.0 tree needs a
separate location. Do not place a Pixel tree in the Realme mount. Logs and artifact
checks are profile-specific. See [README](README.md) and [Realme details](REALME6.md).
