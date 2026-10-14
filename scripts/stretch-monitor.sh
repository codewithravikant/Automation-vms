#!/usr/bin/env bash
# Stretch: install Netdata on every VM (optional — not part of make create).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

require_vagrant
require_guests_up

echo "========================================"
echo " Automation-VMs — stretch monitor (Netdata)"
echo "========================================"
echo ""
echo "Default provisioning is unchanged. This target is opt-in only."
echo "Opens UFW for port 19999 from 10.10.0.0/24 only."
echo ""

while IFS='|' read -r name ip; do
  echo "==> ${name} (${ip})"
  guest_root "${name}" "STRETCH_OPEN_UFW=1 bash /opt/automation-alchemy/monitoring/netdata.sh"
  echo "    UI: http://${ip}:19999"
  echo ""
done < <(list_machines)

echo "========================================"
echo " Netdata installed on all VMs"
echo "========================================"
echo "Open e.g. http://10.10.0.10:19999 from the VirtualBox host."
