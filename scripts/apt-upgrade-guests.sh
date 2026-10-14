#!/usr/bin/env bash
# apt update && apt upgrade on every lab VM, one at a time.
# Does not run inside make alchemy's provision step.
#
#   ./scripts/apt-upgrade-guests.sh              # foreground
#   ./scripts/apt-upgrade-guests.sh --background # detach; log in logs/apt-upgrade.log
#
# HOLD_JENKINS on cicd when ALCHEMY_FROM_JENKINS=1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

LOG_DIR="${ROOT}/logs"
LOG_FILE="${LOG_DIR}/apt-upgrade.log"
PID_FILE="${LOG_DIR}/apt-upgrade.pid"

already_running() {
  [[ -f "${PID_FILE}" ]] || return 1
  local pid
  pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

if [[ "${1:-}" == "--background" ]]; then
  mkdir -p "${LOG_DIR}"
  if already_running; then
    echo "apt upgrade already running (pid $(cat "${PID_FILE}"))."
    echo "Log: ${LOG_FILE}"
    exit 0
  fi
  nohup "$0" --worker >>"${LOG_FILE}" 2>&1 &
  echo $! >"${PID_FILE}"
  echo "apt upgrade started in background (pid $(cat "${PID_FILE}"))."
  echo "Log: ${LOG_FILE}"
  echo "Follow: tail -f ${LOG_FILE}"
  exit 0
fi

if [[ "${1:-}" == "--worker" ]]; then
  shift
fi

require_vagrant
require_guests_up

echo "========================================"
echo " Automation-VMs — apt upgrade guests"
echo " $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "========================================"

failed=0
while IFS='|' read -r name ip; do
  echo ""
  echo "==> ${name} (${ip})"
  cmd="bash /opt/automation-alchemy/provisioning/apt-upgrade-guest.sh"
  if [[ "${name}" == "cicd" && "${ALCHEMY_FROM_JENKINS:-}" == "1" ]]; then
    echo "    Jenkins build is running — not upgrading the jenkins package"
    cmd="HOLD_JENKINS=1 ${cmd}"
  fi
  if guest_root "${name}" "${cmd}"; then
    echo "==> ${name} done"
  else
    echo "==> ${name} FAILED" >&2
    failed=1
  fi
done < <(list_machines)

echo ""
if [[ "${failed}" -ne 0 ]]; then
  echo "One or more guests failed apt upgrade." >&2
  exit 1
fi
echo "All guests upgraded."
