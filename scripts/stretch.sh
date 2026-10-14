#!/usr/bin/env bash
# Stretch: run IPS + VPN + monitoring helpers (all optional).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo " Automation-VMs — stretch (all)"
echo "========================================"
echo ""

"${SCRIPT_DIR}/stretch-ips.sh"
echo ""
"${SCRIPT_DIR}/stretch-vpn.sh"
echo ""
"${SCRIPT_DIR}/stretch-monitor.sh"

echo ""
echo "All stretch extras applied. Base make create / verify behavior unchanged."
