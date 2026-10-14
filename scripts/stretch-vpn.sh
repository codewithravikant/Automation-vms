#!/usr/bin/env bash
# Stretch: set up WireGuard hub-spoke overlay (optional — not part of make create).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

HUB_NAME="${WG_HUB:-loadbalancer}"

require_vagrant
require_guests_up

echo "========================================"
echo " Automation-VMs — stretch VPN (WireGuard)"
echo "========================================"
echo ""
echo "Overlay: 10.66.0.0/24  hub=${HUB_NAME}"
echo "Default provisioning is unchanged. This target is opt-in only."
echo ""

echo "==> Generating keys/configs on ${HUB_NAME}"
guest_root "${HUB_NAME}" "bash /opt/automation-alchemy/security/wireguard-gen.sh"
echo ""

while IFS='|' read -r name ip; do
  echo "==> Applying WireGuard on ${name} (${ip})"
  guest_root "${name}" "bash /opt/automation-alchemy/security/wireguard-apply.sh"
  echo ""
done < <(list_machines)

echo "========================================"
echo " WireGuard overlay ready"
echo "========================================"
echo "Ping overlay (from hub):"
echo "  vagrant ssh ${HUB_NAME} -c 'ping -c 2 10.66.0.11'"
echo "Show interface:"
echo "  vagrant ssh ${HUB_NAME} -c 'sudo wg show'"
