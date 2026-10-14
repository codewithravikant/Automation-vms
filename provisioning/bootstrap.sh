#!/bin/bash
# Provisioning orchestrator — runs all modules in review order.
# Invoked by Vagrant as root on each guest.

set -euo pipefail

# Prefer synced project tree; fall back to directory next to this uploaded script
PROJECT_ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
if [[ -d "${PROJECT_ROOT}/provisioning" ]]; then
  SCRIPT_DIR="${PROJECT_ROOT}/provisioning"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

export PROJECT_ROOT

echo "========================================"
echo " Automation-VMs — provisioning"
echo " Host: ${VM_HOSTNAME:-unknown}  IP: ${VM_IP:-unknown}"
echo "========================================"

export DEBIAN_FRONTEND=noninteractive

echo "==> Pointing apt at HTTPS mirrors"
bash "${SCRIPT_DIR}/apt-https.sh"

apt_try() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if "$@"; then
      return 0
    fi
    echo "==> apt failed (attempt ${attempt}/5); retrying in 20s"
    sleep 20
  done
  return 1
}

echo "==> Updating package index"
apt_try apt-get update -qq
apt_try apt-get -y -qq upgrade --fix-missing

run_step() {
  local name="$1"
  local script="${SCRIPT_DIR}/${name}"
  if [[ -f "${script}" ]]; then
    echo ""
    bash "${script}"
  else
    echo "Missing provisioning script: ${script}" >&2
    exit 1
  fi
}

# Order matches assignment review checklist
run_step hosts.sh
run_step packages.sh
run_step users.sh
run_step ssh.sh
run_step firewall.sh
run_step umask.sh
run_step updates.sh
run_step docker.sh
run_step backup-export.sh

# HTTP entry point — loadbalancer only (browser-accessible)
if [[ "${VM_HOSTNAME:-}" == "loadbalancer" ]]; then
  run_step loadbalancer.sh
fi

# Backup host: weekly rsync destinations + timer
if [[ "${VM_HOSTNAME:-}" == "backup" ]]; then
  run_step backup.sh
fi

echo ""
echo "========================================"
echo " Provisioning complete: ${VM_HOSTNAME:-$(hostname)}"
echo "========================================"
