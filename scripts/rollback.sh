#!/usr/bin/env bash
# Redeploy last-known-good image tags via Ansible.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

ANSIBLE_DIR="${ROOT}/automation"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook not found" >&2
  exit 1
fi

ensure_ssh_key
require_guests_up

echo "========================================"
echo " Automation-VMs — rollback"
echo "========================================"

(
  cd "${ANSIBLE_DIR}"
  ansible-playbook playbooks/rollback.yml
)

bash "${SCRIPT_DIR}/app-verify.sh"
