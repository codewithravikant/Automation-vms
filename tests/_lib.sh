#!/usr/bin/env bash
# Shared helpers for tests/*.sh — source this file.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
# shellcheck source=../scripts/_common.sh
source "${ROOT}/scripts/_common.sh"

pass() {
  printf 'PASS %s\n' "$*"
}

# Print only — callers decide exit status (avoids set -e aborting multi-check scripts).
fail() {
  printf 'FAIL %s\n' "$*"
}

# Run remote command; print stdout. Returns ssh exit status.
remote() {
  local ip="$1"
  shift
  ssh_devops "${ip}" "$@"
}
