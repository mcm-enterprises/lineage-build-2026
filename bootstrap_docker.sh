#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROFILE=${BUILD_PROFILE:-pixel}
if [[ "${1:-}" == --profile && $# -eq 2 ]]; then PROFILE=$2
elif [[ $# -ne 0 ]]; then echo "Usage: $0 [--profile pixel|realme6]" >&2; exit 2; fi
case "$PROFILE" in pixel|realme6) ;; *) echo "Unknown profile: $PROFILE" >&2; exit 2 ;; esac
export BUILD_PROFILE="$PROFILE"
export COMPOSE_PROJECT_NAME="lineage-$PROFILE"
command -v docker >/dev/null || { echo "Install Docker Engine and the Compose v2 plugin." >&2; exit 1; }
docker compose version >/dev/null
docker info >/dev/null
# Keep the user's selected Docker context.
export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
[[ "$HOST_UID" != 0 ]] || { echo "Run as your regular user, not root." >&2; exit 1; }
mkdir -p "$SCRIPT_DIR"/docker_source/"$PROFILE"/{lineage,zips,logs}
for directory in lineage zips logs; do
    [[ -w "$SCRIPT_DIR/docker_source/$PROFILE/$directory" ]] || { echo "Not writable: docker_source/$PROFILE/$directory. Fix its ownership first." >&2; exit 1; }
done
docker compose -f "$SCRIPT_DIR/docker_env/docker-compose.yml" config --quiet
docker compose -f "$SCRIPT_DIR/docker_env/docker-compose.yml" up -d --build
echo "Monitor: BUILD_PROFILE=$PROFILE docker compose -f $SCRIPT_DIR/docker_env/docker-compose.yml logs -f"
echo "Stop: BUILD_PROFILE=$PROFILE docker compose -f $SCRIPT_DIR/docker_env/docker-compose.yml stop"
