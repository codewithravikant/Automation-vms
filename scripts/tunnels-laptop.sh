#!/usr/bin/env bash
# Open all laptop → lab tunnels (SSH local forwards). Keep this terminal open.
#
# Usage (from laptop):
#   ./scripts/tunnels-laptop.sh
#   make tunnels
#   SYNC_HOST=labhost ./scripts/tunnels-laptop.sh
#   TUNNELS_EXTRA=1 ./scripts/tunnels-laptop.sh   # include Netdata + registry
#
# Default Host alias: labhost (set SYNC_HOST / TUNNEL_HOST to match ~/.ssh/config).

set -euo pipefail

HOST="${SYNC_HOST:-${TUNNEL_HOST:-labhost}}"
WITH_EXTRA="${TUNNELS_EXTRA:-1}"

FORWARDS=(
  -L "8080:10.10.0.10:80"           # App / LB
  -L "13000:127.10.10.10:3030"      # Lab dashboard
  -L "18080:10.10.0.40:8080"        # Jenkins UI
)

if [[ "${WITH_EXTRA}" == "1" || "${WITH_EXTRA}" == "true" ]]; then
  FORWARDS+=(
    -L "19999:10.10.0.10:19999"     # Netdata (after make stretch-monitor)
    -L "15000:10.10.0.40:5000"      # Registry catalog (lab-only)
  )
fi

echo "========================================"
echo " Automation-VMs — laptop tunnels"
echo "========================================"
echo "SSH host: ${HOST}"
echo "Keep this terminal open (Ctrl-C to close tunnels)."
echo ""
echo "  App        http://localhost:8080"
echo "  Metrics    http://localhost:8080/api/metrics"
echo "  Dashboard  http://localhost:13000   (run: ssh ${HOST} 'cd ~/automation-vms && make dashboard')"
echo "  Jenkins    http://localhost:18080   (admin / devops)"
if [[ "${WITH_EXTRA}" == "1" || "${WITH_EXTRA}" == "true" ]]; then
  echo "  Netdata    http://localhost:19999   (stretch only)"
  echo "  Registry   http://localhost:15000/v2/_catalog"
fi
echo ""

exec ssh -N "${FORWARDS[@]}" "${HOST}"
