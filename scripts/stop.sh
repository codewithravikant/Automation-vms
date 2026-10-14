#!/usr/bin/env bash
# Gracefully stop all Automation-VMs lab VMs (and the dashboard if running).
# Disks are kept — use `make create` / `make up` to start again.
# To wipe VMs entirely, use `make destroy`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

require_vagrant

echo "========================================"
echo " Automation-VMs — stop / shutdown"
echo "========================================"

# Stop dashboard (preferred port 3030 on 127.10.10.10, or any node dashboard process)
stop_dashboard() {
  local pids=""
  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -tiTCP:3030 -sTCP:LISTEN 2>/dev/null || true)"
  fi
  if [[ -z "${pids}" ]] && command -v pgrep >/dev/null 2>&1; then
    pids="$(pgrep -f 'dashboard.*(node|vite|npm)' 2>/dev/null || true)"
  fi
  if [[ -n "${pids}" ]]; then
    echo "==> Stopping dashboard (pid: ${pids})"
    # shellcheck disable=SC2086
    kill ${pids} 2>/dev/null || true
    sleep 1
    # shellcheck disable=SC2086
    kill -9 ${pids} 2>/dev/null || true
  else
    echo "==> Dashboard not running (nothing on :3030)"
  fi
}

stop_dashboard

echo "==> Halting all VMs (vagrant halt)"
cd_infra
vagrant halt

echo ""
echo "All VMs powered off (disks kept)."
echo "Start again:  make up"
echo "Wipe VMs:     make destroy"
vagrant status
