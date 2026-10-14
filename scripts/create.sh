#!/usr/bin/env bash
# Create / provision the full Automation-VMs environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

# Auto safety check — abort before launching VMs if host is not capable
"${SCRIPT_DIR}/check-host.sh"

require_vagrant
ensure_ssh_key

echo "========================================"
echo " Automation-VMs — create"
echo "========================================"
echo ""
echo "Project key: ${PUBLIC_KEY}"
echo "Infrastructure: ${INFRA_DIR}"
echo ""

cd_infra
vagrant up

echo ""
echo "========================================"
echo " VMs are up"
echo "========================================"
vagrant status
echo ""
echo "SSH as devops (after provision):"
while IFS='|' read -r name ip; do
  echo "  ssh -i keys/id_ed25519 devops@${ip}  # ${name}"
done < <(list_machines)
echo ""
echo "Next: make verify   # or: make review"
