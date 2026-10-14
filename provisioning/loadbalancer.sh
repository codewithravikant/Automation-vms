#!/bin/bash
# Configure nginx as reverse proxy to web1 / web2.
# Only intended for VM_HOSTNAME=loadbalancer.
# Algorithm: LB_ALGORITHM=weighted (default) | least_conn | resource|adaptive

set -euo pipefail

ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
ALGORITHM="${LB_ALGORITHM:-weighted}"

case "${ALGORITHM}" in
  least_conn|least-conn)
    CONF_SRC="${ROOT}/config/nginx-lb.least_conn.conf"
    RESOURCE=0
    ;;
  resource|adaptive|resource-based)
    CONF_SRC="${ROOT}/config/nginx-lb.resource.conf"
    RESOURCE=1
    ALGORITHM="resource"
    ;;
  *)
    CONF_SRC="${ROOT}/config/nginx-lb.conf"
    RESOURCE=0
    ALGORITHM="weighted"
    ;;
esac

echo "==> Configuring load balancer HTTP (nginx, algorithm=${ALGORITHM})"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq nginx

# Disable default site; install our upstream config
rm -f /etc/nginx/sites-enabled/default
cp "${CONF_SRC}" /etc/nginx/sites-available/automation-alchemy-lb
ln -sfn /etc/nginx/sites-available/automation-alchemy-lb /etc/nginx/sites-enabled/automation-alchemy-lb

# Status dir for resource algorithm JSON (also harmless for others)
mkdir -p /var/lib/automation-alchemy
echo "{\"algorithm\":\"${ALGORITHM}\",\"updatedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  >/var/lib/automation-alchemy/lb-status.json
chmod 644 /var/lib/automation-alchemy/lb-status.json

# Adaptive controller (opt-in only)
install -m 755 "${ROOT}/scripts/lb-resource-adapt.sh" /usr/local/sbin/aa-lb-resource-adapt

cat >/etc/systemd/system/aa-lb-resource-adapt.service <<'EOF'
[Unit]
Description=Automation-VMs resource-based LB weight update
After=network-online.target nginx.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/aa-lb-resource-adapt
Nice=10
EOF

cat >/etc/systemd/system/aa-lb-resource-adapt.timer <<'EOF'
[Unit]
Description=Periodic resource-based LB adaptation
[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=5s
Persistent=true
Unit=aa-lb-resource-adapt.service
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload

if [[ "${RESOURCE}" -eq 1 ]]; then
  systemctl enable aa-lb-resource-adapt.timer
  systemctl start aa-lb-resource-adapt.timer
  /usr/local/sbin/aa-lb-resource-adapt || true
else
  systemctl disable --now aa-lb-resource-adapt.timer 2>/dev/null || true
fi

# For non-resource modes, ensure /lb-status exists if referenced — only resource conf has it.
# weighted/least_conn configs do not expose /lb-status; that is fine.

nginx -t
systemctl enable nginx
systemctl restart nginx

echo "==> nginx listening on port 80 → web1/web2 (algorithm=${ALGORITHM})"
ss -tlnp | grep -E ':80\b' || true
