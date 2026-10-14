#!/bin/bash
# Install and enable unattended-upgrades; copy 20auto-upgrades from config/.

set -euo pipefail

ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
AUTO_UPGRADES_SRC="${ROOT}/config/20auto-upgrades"
AUTO_UPGRADES_DST="/etc/apt/apt.conf.d/20auto-upgrades"

echo "==> Configuring automatic updates"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq unattended-upgrades apt-listchanges

if [[ -f "${AUTO_UPGRADES_SRC}" ]]; then
  cp "${AUTO_UPGRADES_SRC}" "${AUTO_UPGRADES_DST}"
else
  cat >"${AUTO_UPGRADES_DST}" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
fi
chmod 644 "${AUTO_UPGRADES_DST}"

systemctl enable unattended-upgrades
systemctl start unattended-upgrades || true

echo "==> Automatic updates enabled"
