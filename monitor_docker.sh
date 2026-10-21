#!/usr/bin/env bash
# Follow one existing workflow and return its container exit status.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROFILE=${BUILD_PROFILE:-pixel}
if [[ $# == 2 && $1 == --profile ]]; then PROFILE=$2
elif [[ $# != 0 ]]; then echo "Usage: bash monitor_docker.sh [--profile pixel|realme6]" >&2; exit 2
fi
case "$PROFILE" in pixel|realme6) ;; *) echo "Unknown profile: $PROFILE" >&2; exit 2 ;; esac
export BUILD_PROFILE="$PROFILE" COMPOSE_PROJECT_NAME="lineage-$PROFILE"
container_id=$(docker compose -f "$SCRIPT_DIR/docker_env/docker-compose.yml" ps -aq lineage-builder)
[[ -n "$container_id" ]] || { echo "No workflow container found for $PROFILE. Run bootstrap_docker.sh first." >&2; exit 1; }
log_pid=
cleanup() {
    if [[ -n "$log_pid" ]]; then
        kill "$log_pid" 2>/dev/null || true
        wait "$log_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'echo "Stopped monitoring; workflow left unchanged."; exit 130' INT
trap 'exit 143' TERM
echo "Monitoring $PROFILE ($container_id). Ctrl+C stops monitoring only."
docker logs --follow "$container_id" &
log_pid=$!
code=$(docker wait "$container_id")
[[ "$code" =~ ^[0-9]+$ && "$code" -le 255 ]] || { echo "Invalid container exit status: $code" >&2; exit 1; }
cleanup
log_pid=
# Fetch final lines again so stopping the follower cannot hide completion output.
echo "--- Final log lines ---"
docker logs --tail 10 "$container_id"
if [[ "$code" == 0 ]]; then
    echo "SUCCESS: $PROFILE workflow finished (exit 0)."
else
    echo "FAILED: $PROFILE workflow finished (exit $code)." >&2
fi
exit "$code"
