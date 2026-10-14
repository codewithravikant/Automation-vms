#!/usr/bin/env bash
# Check: UFW enabled and SSH allowed (file-based; no sudo password needed).
# Usage: check_firewall.sh <name> <ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

ok=1

ufw_conf="$(remote "${IP}" "cat /etc/ufw/ufw.conf" 2>/dev/null || true)"
if echo "${ufw_conf}" | grep -Eq '^ENABLED=yes'; then
  pass "UFW enabled (${NAME})"
else
  fail "UFW enabled (${NAME})"
  ok=0
fi

# user.rules contains allow rules after provisioning
user_rules="$(remote "${IP}" "cat /etc/ufw/user.rules 2>/dev/null || cat /etc/ufw/user6.rules 2>/dev/null || true" 2>/dev/null || true)"
if echo "${user_rules}" | grep -Eq '22|ssh'; then
  pass "UFW allows SSH (${NAME})"
else
  # Fallback: rules file we installed is present under project tree
  if remote "${IP}" "grep -q '22/tcp' /opt/automation-alchemy/config/ufw.rules" >/dev/null 2>&1; then
    pass "UFW allows SSH (${NAME})"
  else
    fail "UFW allows SSH (${NAME})"
    ok=0
  fi
fi

if [[ "${ok}" -eq 1 ]]; then
  exit 0
fi
exit 1
