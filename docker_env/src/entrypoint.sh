#!/usr/bin/env bash
set -euo pipefail
git config --global user.name "Lineage Builder"
git config --global user.email "builder@localhost"
exec /opt/lineage-build/build-lineage.sh "$@"
