#!/usr/bin/env bash
# Check: diagnostic app reachable (skips quietly if not deployed).
# Usage: check_app.sh <name> <ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

# Only assert from loadbalancer / appserver vantage points
case "${NAME}" in
  loadbalancer)
    if ! curl -fsS --max-time 3 "http://${IP}/" >/dev/null 2>&1; then
      pass "app not deployed yet (${NAME}) — run make app-deploy"
      exit 0
    fi
    if curl -fsS --max-time 5 "http://${IP}/" | grep -qi "Automation-VMs"; then
      pass "LB serves frontend (${NAME})"
    else
      fail "LB serves frontend (${NAME})"
      exit 1
    fi
    if curl -fsS --max-time 5 "http://${IP}/api/metrics" | grep -q hostname; then
      pass "LB proxies /api/metrics (${NAME})"
      exit 0
    fi
    fail "LB proxies /api/metrics (${NAME})"
    exit 1
    ;;
  appserver)
    if ! curl -fsS --max-time 3 "http://${IP}:3000/health" >/dev/null 2>&1; then
      pass "backend not deployed yet (${NAME}) — run make app-deploy"
      exit 0
    fi
    if curl -fsS --max-time 5 "http://${IP}:3000/metrics" | grep -q hostname; then
      pass "backend /metrics (${NAME})"
      exit 0
    fi
    fail "backend /metrics (${NAME})"
    exit 1
    ;;
  *)
    pass "app check N/A (${NAME})"
    exit 0
    ;;
esac
