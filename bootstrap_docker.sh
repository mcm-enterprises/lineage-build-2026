#!/bin/bash
set -e

echo ">> [$(date)] Bootstrapping Docker Build Environment..."

# 1. Check Docker
if ! command -v docker &> /dev/null; then
    echo "Error: 'docker' command not found. Please install Docker Engine."
    echo "  sudo apt install docker.io docker-compose-v2"
    exit 1
fi

# 2. Switch Context (Crucial for I/O performance)
CURRENT_CONTEXT=$(docker context show)
if [ "$CURRENT_CONTEXT" != "default" ]; then
    echo ">> Switching Docker context from '$CURRENT_CONTEXT' to 'default' (Native Engine)..."
    docker context use default || echo "Warning: Could not switch context. If using Docker Desktop, performance may be poor."
else
    echo ">> Docker context is 'default' (Good)."
fi

# 3. Create Source Directories
echo ">> Creating isolated source directories in docker_source/..."
mkdir -p docker_source/lineage
mkdir -p docker_source/zips
mkdir -p docker_source/ccache

# 4. Permissions Check
# Ensure current user owns these folders so Docker doesn't make them root-only
# (Our entrypoint handles the interior, but the folder itself must be accessible)
# We assume the user running this script is the owner.

# 5. Launch
echo ">> Building and Starting Container..."
cd docker_env
docker compose up -d --build

echo ">> [$(date)] Docker Build Started!"
echo ">> Monitor logic: docker logs -f lineage-builder-husky"
