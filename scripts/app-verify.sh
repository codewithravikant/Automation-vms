#!/usr/bin/env bash
# Verify diagnostic app through the load balancer and direct backend.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

pass=0
fail=0

ok() { echo "  PASS  $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $*"; fail=$((fail + 1)); }

ip_for() {
  local want="$1"
  while IFS='|' read -r name ip; do
    if [[ "${name}" == "${want}" ]]; then
      echo "${ip}"
      return 0
    fi
  done < <(list_machines)
  return 1
}

echo "========================================"
echo " Automation-VMs — app verify"
echo "========================================"

LB_IP="$(ip_for loadbalancer)"
APP_IP="$(ip_for appserver)"

echo "==> Backend health (${APP_IP}:3000)"
if curl -fsS --max-time 5 "http://${APP_IP}:3000/health" | grep -q ok; then
  ok "backend /health"
else
  bad "backend /health"
fi

echo "==> Backend metrics"
if curl -fsS --max-time 5 "http://${APP_IP}:3000/metrics" | grep -q hostname; then
  ok "backend /metrics"
else
  bad "backend /metrics"
fi

echo "==> Frontend via LB (${LB_IP})"
if curl -fsS --max-time 5 "http://${LB_IP}/" | grep -qi "Automation-VMs"; then
  ok "LB serves frontend"
else
  bad "LB serves frontend"
fi

echo "==> API via LB proxy"
if curl -fsS --max-time 5 "http://${LB_IP}/api/metrics" | grep -q hostname; then
  ok "LB /api/metrics"
else
  bad "LB /api/metrics"
fi

echo "==> LB alternation (web server identity)"
seen_web1=0
seen_web2=0
for _ in $(seq 1 20); do
  html="$(curl -fsS --max-time 5 "http://${LB_IP}/" || true)"
  echo "${html}" | grep -q 'content="web1"' && seen_web1=1
  echo "${html}" | grep -q 'content="web2"' && seen_web2=1
  echo "${html}" | grep -q '__WEB_SERVER__="web1"' && seen_web1=1
  echo "${html}" | grep -q '__WEB_SERVER__="web2"' && seen_web2=1
done
if [[ "${seen_web1}" -eq 1 && "${seen_web2}" -eq 1 ]]; then
  ok "saw both web1 and web2 via LB"
elif [[ "${seen_web1}" -eq 1 || "${seen_web2}" -eq 1 ]]; then
  bad "only one web server seen (web1=${seen_web1} web2=${seen_web2}) — try more requests or check weights"
else
  bad "could not detect web1/web2 identity meta tags"
fi

echo ""
echo "Result: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
