#!/bin/bash
# Optional stretch: install and enable fail2ban for SSH.
# Not required for Layer 1 assignment marks. Not invoked by bootstrap.

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

if ! command -v fail2ban-client >/dev/null 2>&1; then
  # Full apt update OOMs on 512MB guests; try install first, update only if needed.
  if ! apt-get install -y -qq fail2ban; then
    apt-get update -qq
    apt-get install -y -qq fail2ban
  fi
fi

# SSH jail — bantime/maxretry tuned for a lab (still useful for demos)
mkdir -p /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# Socket appears slightly after restart; avoid noisy false failures.
for _ in 1 2 3 4 5; do
  if [[ -S /var/run/fail2ban/fail2ban.sock ]]; then
    break
  fi
  sleep 1
done

echo "fail2ban installed and enabled (sshd jail)"
fail2ban-client status sshd || true
