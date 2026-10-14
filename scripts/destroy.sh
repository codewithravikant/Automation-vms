#!/usr/bin/env bash
# Destroy all Automation-VMs lab VMs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

require_vagrant

echo "========================================"
echo " Automation-VMs — destroy"
echo "========================================"

cd_infra
vagrant destroy -f

echo ""
echo "All VMs destroyed."
