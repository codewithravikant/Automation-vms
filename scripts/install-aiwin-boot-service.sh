#!/usr/bin/env bash
# One-time (or idempotent) install of aiwin boot ensure + path-limited webhook proxy.
# Run on aiwin: sudo ./scripts/install-aiwin-boot-service.sh
#
# Listens on WEBHOOK_PROXY_PORT (default 18081) and ONLY allows:
#   /generic-webhook-trigger/
# Full Jenkins UI stays on 10.10.0.40:8080 (lab CIDR) — access via laptop SSH tunnel.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
UNIT_DST="/etc/systemd/system/alchemy-boot-ensure.service"
PROXY_PORT="${WEBHOOK_PROXY_PORT:-18081}"
JENKINS_UPSTREAM="${JENKINS_UPSTREAM:-10.10.0.40:8080}"
NGINX_CONF="/etc/nginx/sites-available/alchemy-webhook.conf"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

RUN_USER="${SUDO_USER:-labuser}"

apt-get update -qq
apt-get install -y -qq nginx curl

# Remove default site conflict on :80 if present is fine; we only bind PROXY_PORT
install -d -m 0755 /usr/local/lib/automation-alchemy
install -m 0755 "${ROOT}/scripts/aiwin-boot-ensure.sh" /usr/local/lib/automation-alchemy/aiwin-boot-ensure.sh

cat > "${NGINX_CONF}" <<EOF
# Automation-VMs — Git webhook ingress only (do not expose full Jenkins)
server {
    listen ${PROXY_PORT} default_server;
    listen [::]:${PROXY_PORT} default_server;
    server_name _;

    # Deny everything by default (Jenkins UI, login, API, …)
    location / {
        default_type text/plain;
        return 403 "Forbidden: webhook path only. Use SSH tunnel for Jenkins UI.\\n";
    }

    # Git forge → Generic Webhook Trigger
    location /generic-webhook-trigger/ {
        proxy_pass http://${JENKINS_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
}
EOF

ln -sfn "${NGINX_CONF}" /etc/nginx/sites-enabled/alchemy-webhook.conf
# Avoid default site grabbing our port accidentally
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

nginx -t
systemctl enable nginx
systemctl reload nginx || systemctl restart nginx

# Kill legacy full-TCP socat if present
pkill -f "socat TCP-LISTEN:18080" 2>/dev/null || true
rm -f /run/alchemy-webhook-proxy.pid

cat > "${UNIT_DST}" <<EOF
[Unit]
Description=Automation-VMs boot ensure (VMs + webhook-only nginx)
After=network-online.target nginx.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=root
Environment=WEBHOOK_PROXY_PORT=${PROXY_PORT}
Environment=JENKINS_UPSTREAM=${JENKINS_UPSTREAM}
WorkingDirectory=${ROOT}
ExecStart=/usr/local/lib/automation-alchemy/aiwin-boot-ensure.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable alchemy-boot-ensure.service
systemctl restart alchemy-boot-ensure.service

echo ""
echo "Installed alchemy-boot-ensure.service + nginx webhook proxy"
echo "Webhook-only listen: 0.0.0.0:${PROXY_PORT}  (path /generic-webhook-trigger/ only)"
echo "Jenkins UI is NOT on this port — use laptop SSH tunnel to 10.10.0.40:8080"
echo ""
echo "Git forge webhook URL:"
echo "  http://<virtualbox-host-ip>:${PROXY_PORT}/generic-webhook-trigger/invoke?token=<secret>"
echo ""
echo "Host firewall (webhook only):"
echo "  sudo ufw allow ${PROXY_PORT}/tcp comment 'git webhook proxy'"
echo "  # Prefer: sudo ufw allow from <git-forge-ip> to any port ${PROXY_PORT} proto tcp"
echo ""
echo "Laptop Jenkins UI (keep tunnel open):"
echo "  ssh -L 8080:10.10.0.10:80 -L 13000:127.10.10.10:3030 -L 18080:10.10.0.40:8080 ${RUN_USER}@<virtualbox-host>"
echo "  → http://localhost:18080  (admin / devops)"
