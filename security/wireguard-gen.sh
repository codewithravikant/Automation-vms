#!/bin/bash
# Generate WireGuard keys + configs for the lab overlay (10.66.0.0/24).
# Run once as root on any guest (typically loadbalancer). Writes into the
# synced project tree so every VM can apply its peer config.
# Not invoked by bootstrap.

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

PROJECT_ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
MACHINES_YML="${PROJECT_ROOT}/infrastructure/machines.yml"
OUT_DIR="${PROJECT_ROOT}/keys/wireguard"
HUB_NAME="${WG_HUB:-loadbalancer}"
WG_PORT="${WG_PORT:-51820}"
WG_NET_PREFIX="10.66.0"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq wireguard wireguard-tools

if [[ ! -f "${MACHINES_YML}" ]]; then
  echo "Missing ${MACHINES_YML}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
chmod 700 "${OUT_DIR}" 2>/dev/null || true

# Parse name|ip from machines.yml (same shape as scripts/_common.sh list_machines)
mapfile -t MACHINES < <(awk '
  /^machines:/ { in_m=1; next }
  in_m && /^[^ #]/ { in_m=0 }
  in_m && /^  [a-zA-Z0-9_-]+:/ {
    name=$1
    sub(/:$/, "", name)
    getline
    if ($1 ~ /^ip:/) {
      ip=$2
      print name "|" ip
    }
  }
' "${MACHINES_YML}")

if [[ "${#MACHINES[@]}" -eq 0 ]]; then
  echo "No machines found in ${MACHINES_YML}" >&2
  exit 1
fi

wg_ip_for() {
  local priv_ip="$1"
  local last
  last="${priv_ip##*.}"
  echo "${WG_NET_PREFIX}.${last}"
}

declare -A PRIV_KEY PUB_KEY PRIV_IP WG_IP

HUB_PRIV_IP=""
for entry in "${MACHINES[@]}"; do
  name="${entry%%|*}"
  ip="${entry##*|}"
  PRIV_IP["${name}"]="${ip}"
  WG_IP["${name}"]="$(wg_ip_for "${ip}")"

  key_file="${OUT_DIR}/${name}.key"
  if [[ -f "${key_file}" ]]; then
    PRIV_KEY["${name}"]="$(tr -d '\n' <"${key_file}")"
  else
    PRIV_KEY["${name}"]="$(wg genkey)"
    printf '%s\n' "${PRIV_KEY[${name}]}" >"${key_file}"
    chmod 600 "${key_file}" 2>/dev/null || true
  fi
  PUB_KEY["${name}"]="$(printf '%s' "${PRIV_KEY[${name}]}" | wg pubkey)"
  printf '%s\n' "${PUB_KEY[${name}]}" >"${OUT_DIR}/${name}.pub"
  chmod 644 "${OUT_DIR}/${name}.pub" 2>/dev/null || true

  if [[ "${name}" == "${HUB_NAME}" ]]; then
    HUB_PRIV_IP="${ip}"
  fi
done

if [[ -z "${HUB_PRIV_IP}" ]]; then
  echo "Hub machine '${HUB_NAME}' not found in machines.yml" >&2
  exit 1
fi

# Hub config: listen + one Peer stanza per spoke
{
  echo "[Interface]"
  echo "Address = ${WG_IP[${HUB_NAME}]}/24"
  echo "ListenPort = ${WG_PORT}"
  echo "PrivateKey = ${PRIV_KEY[${HUB_NAME}]}"
  echo ""
  for entry in "${MACHINES[@]}"; do
    name="${entry%%|*}"
    [[ "${name}" == "${HUB_NAME}" ]] && continue
    echo "[Peer]"
    echo "# ${name}"
    echo "PublicKey = ${PUB_KEY[${name}]}"
    echo "AllowedIPs = ${WG_IP[${name}]}/32"
    echo ""
  done
} >"${OUT_DIR}/${HUB_NAME}.conf"
chmod 600 "${OUT_DIR}/${HUB_NAME}.conf" 2>/dev/null || true

# Spoke configs: connect to hub over the private network
for entry in "${MACHINES[@]}"; do
  name="${entry%%|*}"
  [[ "${name}" == "${HUB_NAME}" ]] && continue
  {
    echo "[Interface]"
    echo "Address = ${WG_IP[${name}]}/24"
    echo "PrivateKey = ${PRIV_KEY[${name}]}"
    echo ""
    echo "[Peer]"
    echo "# ${HUB_NAME}"
    echo "PublicKey = ${PUB_KEY[${HUB_NAME}]}"
    echo "Endpoint = ${HUB_PRIV_IP}:${WG_PORT}"
    echo "AllowedIPs = ${WG_NET_PREFIX}.0/24"
    echo "PersistentKeepalive = 25"
  } >"${OUT_DIR}/${name}.conf"
  chmod 600 "${OUT_DIR}/${name}.conf" 2>/dev/null || true
done

cat >"${OUT_DIR}/README.txt" <<EOF
WireGuard overlay (stretch) — generated $(date -u +%Y-%m-%dT%H:%MZ)
Network: ${WG_NET_PREFIX}.0/24
Hub: ${HUB_NAME} (${HUB_PRIV_IP}:${WG_PORT} → ${WG_IP[${HUB_NAME}]})
Apply on each VM: sudo bash /opt/automation-alchemy/security/wireguard-apply.sh
EOF

echo "==> WireGuard configs written to ${OUT_DIR}"
ls -la "${OUT_DIR}"
