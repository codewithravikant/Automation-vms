#!/bin/bash
# Apply UFW rules from config/ufw.rules and enable the firewall.

set -euo pipefail

ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
RULES_FILE="${ROOT}/config/ufw.rules"
if [[ ! -f "${RULES_FILE}" && -f "${ROOT}/security/ufw.rules" ]]; then
  RULES_FILE="${ROOT}/security/ufw.rules"
fi

echo "==> Configuring UFW"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq ufw

ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing

apply_rules_file() {
  local file="$1"
  [[ -f "${file}" ]] || return 0
  while IFS= read -r rule || [[ -n "${rule}" ]]; do
    [[ -z "${rule}" || "${rule}" =~ ^# ]] && continue
    # Multi-word rules must split into argv words. Quoting the whole line
    # makes ufw treat it as a single port → "ERROR: Bad port".
    # Trusted local config only. shellcheck disable=SC2086
    ufw allow ${rule}
  done < "${file}"
}

if [[ -f "${RULES_FILE}" ]]; then
  apply_rules_file "${RULES_FILE}"
else
  ufw allow 22/tcp
fi

# Role overlay: e.g. config/ufw.rules.loadbalancer → allow 80/tcp
HOST_NAME="${VM_HOSTNAME:-$(hostname -s)}"
ROLE_RULES="${ROOT}/config/ufw.rules.${HOST_NAME}"
if [[ -f "${ROLE_RULES}" ]]; then
  echo "==> Applying role UFW rules: ${ROLE_RULES}"
  apply_rules_file "${ROLE_RULES}"
fi

ufw --force enable
ufw status verbose

echo "==> UFW enabled"
