#!/usr/bin/env bash
# Show Vagrant status and quick reachability for each VM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

require_vagrant

echo "========================================"
echo " Automation-VMs — status"
echo "========================================"
echo ""

cd_infra
vagrant status
echo ""

echo "Network / SSH quick check:"
while IFS='|' read -r name ip; do
  if ping -c 1 -W 2 "${ip}" >/dev/null 2>&1; then
    ping_ok="ping OK"
  else
    ping_ok="ping FAIL"
  fi

  if [[ -f "${PRIVATE_KEY}" ]] && ssh_devops "${ip}" "true" >/dev/null 2>&1; then
    ssh_ok="SSH OK"
  else
    ssh_ok="SSH FAIL"
  fi

  printf "  %-14s %-15s %-10s %s\n" "${name}" "${ip}" "${ping_ok}" "${ssh_ok}"
done < <(list_machines)
