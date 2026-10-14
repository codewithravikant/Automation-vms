#!/usr/bin/env bash
# VirtualBox host boot helper: bring lab VMs + path-limited Git→Jenkins webhook proxy up.
# NEVER runs make alchemy.
#
# Security: host :WEBHOOK_PROXY_PORT only proxies /generic-webhook-trigger/*
# Full Jenkins UI is NOT exposed on the LAN — use laptop SSH tunnels instead.
#
# Install: sudo ./scripts/install-aiwin-boot-service.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROXY_PORT="${WEBHOOK_PROXY_PORT:-18081}"
JENKINS_UPSTREAM="${JENKINS_UPSTREAM:-10.10.0.40:8080}"
NGINX_CONF="${NGINX_CONF:-/etc/nginx/sites-available/alchemy-webhook.conf}"
NGINX_ENABLED="${NGINX_ENABLED:-/etc/nginx/sites-enabled/alchemy-webhook.conf}"

echo "========================================"
echo " Automation-VMs — host boot ensure"
echo "========================================"

cd "${ROOT}"

if [[ -d "${ROOT}/infrastructure" ]] && command -v vagrant >/dev/null 2>&1; then
  echo "==> Ensuring Vagrant VMs are up (no reprovision)"
  (
    cd "${ROOT}/infrastructure"
    vagrant up --no-provision || vagrant up
  )
else
  echo "==> Skip vagrant (missing or not installed)"
fi

# Stop legacy full-TCP socat proxy if still running (exposed entire Jenkins UI)
if [[ -f /run/alchemy-webhook-proxy.pid ]]; then
  oldpid="$(cat /run/alchemy-webhook-proxy.pid 2>/dev/null || true)"
  if [[ -n "${oldpid}" ]] && kill -0 "${oldpid}" 2>/dev/null; then
    echo "==> Stopping legacy socat webhook proxy (pid ${oldpid})"
    kill "${oldpid}" 2>/dev/null || true
  fi
  rm -f /run/alchemy-webhook-proxy.pid
fi
pkill -f "socat TCP-LISTEN:18080" 2>/dev/null || true

echo "==> Webhook-only nginx :${PROXY_PORT} → ${JENKINS_UPSTREAM} (path /generic-webhook-trigger/)"
if command -v nginx >/dev/null 2>&1 && [[ -f "${NGINX_CONF}" ]]; then
  if [[ ! -L "${NGINX_ENABLED}" && ! -f "${NGINX_ENABLED}" ]]; then
    ln -sf "${NGINX_CONF}" "${NGINX_ENABLED}" 2>/dev/null || true
  fi
  if nginx -t 2>/dev/null; then
    systemctl is-active --quiet nginx 2>/dev/null && systemctl reload nginx || systemctl start nginx || nginx
    echo "    nginx webhook proxy ready on :${PROXY_PORT}"
  else
    echo "WARNING: nginx -t failed — check ${NGINX_CONF}" >&2
  fi
else
  echo "WARNING: nginx site not installed — run: sudo ./scripts/install-aiwin-boot-service.sh" >&2
fi

echo "==> Wait for Jenkins on ${JENKINS_UPSTREAM}"
deadline=$((SECONDS + 180))
while (( SECONDS < deadline )); do
  if curl -sf -o /dev/null --connect-timeout 2 "http://${JENKINS_UPSTREAM}/login"; then
    echo "    Jenkins is reachable (lab CIDR / tunnels only for UI)"
    echo " Boot ensure DONE (no make alchemy)"
    exit 0
  fi
  sleep 5
done

echo "WARNING: Jenkins not reachable yet at http://${JENKINS_UPSTREAM}/login" >&2
echo " Boot ensure finished with warnings (no make alchemy)"
exit 0
