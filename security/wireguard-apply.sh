#!/bin/bash
# Apply this VM's WireGuard peer config and start wg-quick@wg0.
# Expects keys/wireguard/<hostname>.conf from wireguard-gen.sh.
# Not invoked by bootstrap.

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

PROJECT_ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
OUT_DIR="${PROJECT_ROOT}/keys/wireguard"
HUB_NAME="${WG_HUB:-loadbalancer}"
WG_PORT="${WG_PORT:-51820}"
HOST_NAME="$(hostname -s)"
CONF_SRC="${OUT_DIR}/${HOST_NAME}.conf"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq wireguard wireguard-tools

if [[ ! -f "${CONF_SRC}" ]]; then
  echo "Missing ${CONF_SRC}. Run wireguard-gen.sh first." >&2
  exit 1
fi

install -d -m 700 /etc/wireguard
install -m 600 "${CONF_SRC}" /etc/wireguard/wg0.conf

# Hub must accept WireGuard UDP; do not rewrite base UFW templates
if [[ "${HOST_NAME}" == "${HUB_NAME}" ]]; then
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${WG_PORT}/udp" comment 'automation-alchemy-wireguard' || true
    ufw status | grep -E "${WG_PORT}/udp" || true
  fi
fi

systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo "==> WireGuard wg0 up on ${HOST_NAME}"
wg show || true
ip -4 addr show wg0 || true
