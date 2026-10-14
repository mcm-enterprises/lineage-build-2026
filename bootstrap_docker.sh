#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command -v docker >/dev/null || { echo "Install Docker Engine and the Compose v2 plugin." >&2; exit 1; }
docker compose version >/dev/null
docker info >/dev/null
# Keep the user's selected Docker context.
export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
[[ "$HOST_UID" != 0 ]] || { echo "Run as your regular user, not root." >&2; exit 1; }
mkdir -p "$SCRIPT_DIR"/docker_source/{lineage,zips,logs}
for directory in lineage zips logs; do
    [[ -w "$SCRIPT_DIR/docker_source/$directory" ]] || { echo "Not writable: docker_source/$directory. Fix its ownership first." >&2; exit 1; }
done
docker compose -f "$SCRIPT_DIR/docker_env/docker-compose.yml" config --quiet
docker compose -f "$SCRIPT_DIR/docker_env/docker-compose.yml" up -d --build
echo "Monitor: docker compose -f $SCRIPT_DIR/docker_env/docker-compose.yml logs -f"
echo "Stop: docker compose -f $SCRIPT_DIR/docker_env/docker-compose.yml stop"
