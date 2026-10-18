#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROFILE=${BUILD_PROFILE:-pixel}
if [[ $(uname -s) == Darwin ]]; then
    ACTION=${BUILD_ACTION:-sync}
    export SYNC_JOBS=${SYNC_JOBS:-2}
    export JOBS=${JOBS:-1}
else
    ACTION=${BUILD_ACTION:-all}
fi
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile|--action)
            [[ $# -ge 2 ]] || { echo "$1 requires a value" >&2; exit 2; }
            if [[ "$1" == --profile ]]; then PROFILE=$2; else ACTION=$2; fi
            shift 2 ;;
        -h|--help) echo "Usage: $0 [--profile pixel|realme6] [--action check|check-network|sync|build|all]"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
case "$ACTION" in check|check-network|sync|build|all) ;; *) echo "Unknown action: $ACTION" >&2; exit 2 ;; esac
export BUILD_ACTION="$ACTION"
case "$PROFILE" in pixel|realme6) ;; *) echo "Unknown profile: $PROFILE" >&2; exit 2 ;; esac
export BUILD_PROFILE="$PROFILE"
export COMPOSE_PROJECT_NAME="lineage-$PROFILE"
command -v docker >/dev/null || { echo "Install Docker Engine and the Compose v2 plugin." >&2; exit 1; }
docker compose version >/dev/null
docker info --format 'Docker VM: {{.OSType}}/{{.Architecture}}, {{.NCPU}} CPUs, {{.MemTotal}} bytes RAM'
if [[ $(uname -s) == Darwin ]]; then
    echo "Docker Desktop: allocate RAM and disk-image capacity in Settings > Resources. Source downloads live in a Linux named volume."
    if [[ $(uname -m) == arm64 ]]; then
        echo "Apple Silicon: this x86_64 Android toolchain uses linux/amd64 emulation; full ROM builds may be very slow or encounter emulation limits."
    fi
fi
# Keep the user's selected Docker context.
export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
[[ "$HOST_UID" != 0 ]] || { echo "Run as your regular user, not root." >&2; exit 1; }
mkdir -p "$SCRIPT_DIR"/docker_source/"$PROFILE"/{zips,logs}
for directory in zips logs; do
    [[ -w "$SCRIPT_DIR/docker_source/$PROFILE/$directory" ]] || { echo "Not writable: docker_source/$PROFILE/$directory. Fix its ownership first." >&2; exit 1; }
done
if [[ -d "$SCRIPT_DIR/docker_source/$PROFILE/lineage/.repo" ]]; then
    echo "Previous bind-mounted source tree is preserved in docker_source/$PROFILE/lineage. The new named volume is separate; see README_DOCKER.md before redownloading."
fi
docker compose -f "$SCRIPT_DIR/docker_env/docker-compose.yml" config --quiet
running=$(docker compose -f "$SCRIPT_DIR/docker_env/docker-compose.yml" ps --status running -q lineage-builder)
[[ -z "$running" ]] || { echo "This profile already has a running workflow. Monitor it or stop it explicitly before launching again." >&2; exit 1; }
docker compose -f "$SCRIPT_DIR/docker_env/docker-compose.yml" up -d --build
echo "Monitor: BUILD_PROFILE=$PROFILE docker compose -f $SCRIPT_DIR/docker_env/docker-compose.yml logs -f"
echo "Stop: BUILD_PROFILE=$PROFILE docker compose -f $SCRIPT_DIR/docker_env/docker-compose.yml stop"
