#!/usr/bin/env bash
# Stretch: install Fail2Ban on every VM (optional — not part of make create).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

require_vagrant
require_guests_up

echo "========================================"
echo " Automation-VMs — stretch IPS (Fail2Ban)"
echo "========================================"
echo ""
echo "Default provisioning is unchanged. This target is opt-in only."
echo ""

while IFS='|' read -r name ip; do
  echo "==> ${name} (${ip})"
  if ! guest_root "${name}" "bash /opt/automation-alchemy/security/fail2ban.sh"; then
    echo "WARNING: Fail2Ban install failed on ${name} — continuing" >&2
  fi
  echo ""
done < <(list_machines)

echo "========================================"
echo " Fail2Ban installed on all VMs"
echo "========================================"
echo "Check: vagrant ssh loadbalancer -c 'sudo fail2ban-client status sshd'"
