#!/bin/bash
# Set hostname and install managed /etc/hosts from config/hosts (or NETWORK_HOSTS).

set -euo pipefail

ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
HOSTS_FILE="${ROOT}/config/hosts"
HOSTS_BLOCK_START="# BEGIN automation-alchemy"
HOSTS_BLOCK_END="# END automation-alchemy"

echo "==> Configuring hostname / hosts resolution"

if [[ -n "${VM_HOSTNAME:-}" ]]; then
  hostnamectl set-hostname "${VM_HOSTNAME}"
fi

# Prefer live NETWORK_HOSTS from Vagrant (derived from network.yml), else config/hosts.
resolve_hosts_body() {
  if [[ -n "${NETWORK_HOSTS:-}" ]]; then
    printf '%s\n' "${NETWORK_HOSTS}"
    return
  fi
  if [[ -f "${HOSTS_FILE}" ]]; then
    # Skip blank lines and comments
    grep -vE '^\s*(#|$)' "${HOSTS_FILE}" || true
    return
  fi
  cat <<'EOF'
10.10.0.10 loadbalancer
10.10.0.11 web1
10.10.0.12 web2
10.10.0.20 appserver
10.10.0.30 backup
10.10.0.40 cicd
EOF
}

TMP_HOSTS="$(mktemp)"
awk -v start="${HOSTS_BLOCK_START}" -v end="${HOSTS_BLOCK_END}" '
  $0 == start {skip=1; next}
  $0 == end {skip=0; next}
  !skip {print}
' /etc/hosts > "${TMP_HOSTS}"

{
  cat "${TMP_HOSTS}"
  echo "${HOSTS_BLOCK_START}"
  resolve_hosts_body
  echo "${HOSTS_BLOCK_END}"
} > /etc/hosts

rm -f "${TMP_HOSTS}"

echo "==> Hostname/hosts configured (hostname=$(hostname))"
