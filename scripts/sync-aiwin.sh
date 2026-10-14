#!/usr/bin/env bash
# Sync this repo to the VirtualBox host (excludes node_modules, .vagrant, .git, dist).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${SYNC_HOST:-labhost}"
REMOTE_DIR="${SYNC_REMOTE_DIR:-~/automation-vms}"

ssh "$HOST" "mkdir -p ${REMOTE_DIR}"
rsync -avz \
  --exclude node_modules \
  --exclude .vagrant \
  --exclude .git \
  --exclude dist \
  --exclude '**/node_modules' \
  "${ROOT}/" \
  "${HOST}:${REMOTE_DIR}/"

echo "Synced ${ROOT}/ -> ${HOST}:${REMOTE_DIR}/"
