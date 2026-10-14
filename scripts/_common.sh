#!/usr/bin/env bash
# Shared helpers for scripts/*.sh — source this file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${ROOT}/infrastructure"
MACHINES_YML="${INFRA_DIR}/machines.yml"
KEYS_DIR="${ROOT}/keys"
PRIVATE_KEY="${KEYS_DIR}/id_ed25519"
PUBLIC_KEY="${KEYS_DIR}/id_ed25519.pub"

cd_infra() {
  cd "${INFRA_DIR}"
}

require_vagrant() {
  if ! command -v vagrant >/dev/null 2>&1; then
    echo "vagrant is not installed or not on PATH" >&2
    exit 1
  fi
}

# Parse machine names and IPs from machines.yml without requiring Ruby/yq.
# Outputs lines: name|ip
list_machines() {
  awk '
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
  ' "${MACHINES_YML}"
}

ensure_ssh_key() {
  mkdir -p "${KEYS_DIR}"
  chmod 700 "${KEYS_DIR}"
  if [[ ! -f "${PRIVATE_KEY}" ]]; then
    echo "==> Generating project SSH key at keys/id_ed25519"
    ssh-keygen -t ed25519 -N "" -f "${PRIVATE_KEY}" -C "devops@automation-alchemy"
  fi
  if [[ ! -f "${PUBLIC_KEY}" ]]; then
    echo "Missing public key: ${PUBLIC_KEY}" >&2
    exit 1
  fi
  chmod 600 "${PRIVATE_KEY}"
  chmod 644 "${PUBLIC_KEY}"
}

ssh_devops() {
  local ip="$1"
  shift
  ssh -i "${PRIVATE_KEY}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 \
    -o BatchMode=yes \
    "devops@${ip}" "$@"
}

# Abort unless every lab VM answers ping (stretch helpers need running guests).
require_guests_up() {
  local name ip
  while IFS='|' read -r name ip; do
    if ! ping -c 1 -W 3 "${ip}" >/dev/null 2>&1; then
      echo "VM ${name} (${ip}) is not reachable. Run: make create" >&2
      exit 1
    fi
  done < <(list_machines)
}

# Run a command as root on a guest via vagrant ssh (vagrant has NOPASSWD sudo).
# Does not use devops sudo — keeps passworded sudo intact for review checks.
guest_root() {
  local name="$1"
  shift
  require_vagrant
  (
    cd_infra
    # stdin must be /dev/null — otherwise vagrant ssh steals the rest of a
    # `while read … done < <(list_machines)` loop (only first VM would run).
    # shellcheck disable=SC2029
    vagrant ssh "${name}" -c "sudo bash -lc $(printf '%q' "$*")" </dev/null
  )
}
