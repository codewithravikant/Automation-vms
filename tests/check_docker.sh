#!/usr/bin/env bash
# Check: Docker installed on roles that host containers.
# Usage: check_docker.sh <name> <ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

case "${NAME}" in
  appserver|web1|web2|cicd) ;;
  *)
    pass "docker not required (${NAME})"
    exit 0
    ;;
esac

if remote "${IP}" "command -v docker >/dev/null && docker --version" >/dev/null 2>&1; then
  pass "docker installed (${NAME})"
  exit 0
fi
fail "docker installed (${NAME})"
exit 1
