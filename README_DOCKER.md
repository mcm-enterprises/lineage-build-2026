# Docker build instructions

Use Docker Engine with Compose v2 on an x86_64 Linux host. Allocate at least 300 GiB
free disk and preferably 32 GiB or more RAM. The image uses Ubuntu 22.04 and runs
as an unprivileged user whose UID/GID match the host account.

Start from any directory by invoking the launcher by its path:

```bash
./bootstrap_docker.sh
docker compose -f docker_env/docker-compose.yml logs -f
```

Persistent host directories are `docker_source/lineage`, `docker_source/zips`, and
`docker_source/logs`. The launcher creates them before starting Docker. If an older
container created root-owned directories, fix their ownership before launching.
The source tree is separate from a native build. Old 23.0 trees are rejected;
use a new directory for 22.1 or explicitly move/back up the old tree first.

Check the actual result (a detached launch only means the container started):

```bash
docker compose -f docker_env/docker-compose.yml ps -a
container_id=$(docker compose -f docker_env/docker-compose.yml ps -aq lineage-builder)
docker inspect --format '{{.State.ExitCode}}' "$container_id"
```

Stop this build without affecting other host processes:

```bash
docker compose -f docker_env/docker-compose.yml stop
```

Rerun `./bootstrap_docker.sh` to resume; source sync and completed downloads persist.
To run a stage in the foreground, first stop any active build, then:

```bash
export HOST_UID=$(id -u) HOST_GID=$(id -g)
docker compose -f docker_env/docker-compose.yml run --rm lineage-builder check
docker compose -f docker_env/docker-compose.yml run --rm lineage-builder sync
docker compose -f docker_env/docker-compose.yml run --rm lineage-builder build
```

For manual image builds, export HOST_UID/HOST_GID before `docker compose build` too.
Adjust resources with `JOBS=4 SYNC_JOBS=4 ./bootstrap_docker.sh`. The image has no
fixed 24 GiB cap; job selection considers the available memory. Add host swap if
Soong exhausts RAM. For an already populated tree you can lower the remaining-space
threshold, e.g. `MIN_FREE_GB=100 ./bootstrap_docker.sh`.

Logs include source-sync and compiler output. Vendor files come from the matching
husky Git LFS repository. Sync retries are bounded; the script preserves lock files
and local changes. Success requires a fresh ZIP and exports its checksum and source
manifest. See [README](README.md) for troubleshooting and limitations.
